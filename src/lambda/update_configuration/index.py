# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import json
import os
import logging
import boto3
from botocore.exceptions import ClientError
from typing import Dict, Any, Union
import yaml
from decimal import Decimal

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))
logging.getLogger('idp_common.bedrock.client').setLevel(os.environ.get("BEDROCK_LOG_LEVEL", "INFO"))
# Get LOG_LEVEL from environment variable with INFO as default

dynamodb = boto3.resource('dynamodb')
s3_client = boto3.client('s3')
table = dynamodb.Table(os.environ['CONFIGURATION_TABLE_NAME'])

def fetch_content_from_s3(s3_uri: str) -> Union[Dict[str, Any], str]:
    """
    Fetches content from S3 URI and parses as JSON or YAML if possible
    """
    try:
        # Parse S3 URI
        if not s3_uri.startswith('s3://'):
            raise ValueError(f"Invalid S3 URI: {s3_uri}")
        
        # Remove s3:// prefix and split bucket and key
        s3_path = s3_uri[5:]
        bucket, key = s3_path.split('/', 1)
        
        logger.info(f"Fetching content from S3: bucket={bucket}, key={key}")
        
        # Fetch object from S3
        response = s3_client.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Try to parse as JSON first, then YAML, return as string if both fail
        try:
            return json.loads(content)
        except json.JSONDecodeError:
            try:
                return yaml.safe_load(content)
            except yaml.YAMLError:
                logger.warning(f"Content from {s3_uri} is not valid JSON or YAML, returning as string")
                return content
            
    except ClientError as e:
        logger.error(f"Error fetching content from S3 {s3_uri}: {str(e)}")
        raise
    except Exception as e:
        logger.error(f"Error processing S3 URI {s3_uri}: {str(e)}")
        raise

def convert_floats_to_decimal(obj):
    """
    Recursively convert float values to Decimal for DynamoDB compatibility
    """
    if isinstance(obj, float):
        return Decimal(str(obj))
    elif isinstance(obj, dict):
        return {k: convert_floats_to_decimal(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [convert_floats_to_decimal(item) for item in obj]
    return obj

def resolve_content(content: Union[str, Dict[str, Any]]) -> Union[Dict[str, Any], str]:
    """
    Resolves content - if it's a string starting with s3://, fetch from S3
    Otherwise return as-is
    """
    if isinstance(content, str) and content.startswith('s3://'):
        return fetch_content_from_s3(content)
    return content

def update_configuration(configuration_type: str, data: Dict[str, Any]) -> None:
    """
    Updates or creates a configuration item in DynamoDB
    """
    try:
        # Convert any float values to Decimal for DynamoDB compatibility
        converted_data = convert_floats_to_decimal(data)

        table.put_item(
            Item={
                'Configuration': configuration_type,
                **converted_data
            }
        )
    except ClientError as e:
        logger.error(f"Error updating configuration {configuration_type}: {str(e)}")
        raise

def delete_configuration(configuration_type: str) -> None:
    """
    Deletes a configuration item from DynamoDB
    """
    try:
        table.delete_item(
            Key={
                'Configuration': configuration_type
            }
        )
    except ClientError as e:
        logger.error(f"Error deleting configuration {configuration_type}: {str(e)}")
        raise

def generate_physical_id(stack_id: str, logical_id: str) -> str:
    """
    Generates a consistent physical ID for the custom resource
    """
    return f"{stack_id}/{logical_id}/configuration"

def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Handles configuration management for both CloudFormation and Terraform deployments.
    For Terraform, simply invoke with ResourceProperties directly.
    """
    logger.info(f"Received event: {json.dumps(event)}")

    try:
        # Support both CloudFormation and direct Terraform invocation
        request_type = event.get('RequestType', 'Create')

        # Get properties from ResourceProperties or use empty dict
        # Create a copy to avoid mutating the original event
        resource_properties = event.get('ResourceProperties')
        if resource_properties is None:
            properties = {}
        else:
            properties = dict(resource_properties)

        # Remove ServiceToken from the copied properties (not needed in DynamoDB)
        properties.pop('ServiceToken', None)

        if request_type in ['Create', 'Update']:
            # Update Schema configuration
            if 'Schema' in properties:
                resolved_schema = resolve_content(properties['Schema'])
                update_configuration('Schema', {'Schema': resolved_schema})
                logger.info("Updated Schema configuration")

            # Update Default configuration
            if 'Default' in properties:
                resolved_default = resolve_content(properties['Default'])

                # Apply custom model ARNs if provided
                if isinstance(resolved_default, dict):
                    # Replace classification model if CustomClassificationModelARN is provided and not empty
                    custom_classification_arn = properties.get('CustomClassificationModelARN')
                    if custom_classification_arn and isinstance(custom_classification_arn, str) and custom_classification_arn.strip():
                        if 'classification' in resolved_default:
                            resolved_default['classification']['model'] = custom_classification_arn
                            logger.info(f"Updated classification model to: {custom_classification_arn}")

                    # Replace extraction model if CustomExtractionModelARN is provided and not empty
                    custom_extraction_arn = properties.get('CustomExtractionModelARN')
                    if custom_extraction_arn and isinstance(custom_extraction_arn, str) and custom_extraction_arn.strip():
                        if 'extraction' in resolved_default:
                            resolved_default['extraction']['model'] = custom_extraction_arn
                            logger.info(f"Updated extraction model to: {custom_extraction_arn}")

                update_configuration('Default', resolved_default)
                logger.info("Updated Default configuration")

            # Update Custom configuration if provided and not empty
            if 'Custom' in properties:
                custom_properties = properties.get('Custom')
                if isinstance(custom_properties, dict) and custom_properties.get('Info') != 'Custom inference settings':
                    resolved_custom = resolve_content(custom_properties)
                    update_configuration('Custom', resolved_custom)
                    logger.info("Updated Custom configuration")
                elif not isinstance(custom_properties, dict):
                    logger.warning(f"Custom properties is not a dictionary (type: {type(custom_properties)}), skipping Custom configuration update")

            response_data = {
                'Message': f'Successfully {request_type.lower()}d configurations',
                'Status': 'SUCCESS'
            }

            # For CloudFormation compatibility (if cfnresponse is available)
            if 'StackId' in event:
                try:
                    import cfnresponse
                    physical_id = generate_physical_id(event['StackId'], event['LogicalResourceId'])
                    cfnresponse.send(event, context, cfnresponse.SUCCESS, response_data, physical_id)
                except ImportError:
                    logger.warning("cfnresponse not available, returning direct response")

            return response_data

        elif request_type == 'Delete':
            # Do nothing on delete - preserve configuration data
            logger.info("Delete request - no operation performed")

            response_data = {
                'Message': 'Success (delete = no-op)',
                'Status': 'SUCCESS'
            }

            # For CloudFormation compatibility
            if 'StackId' in event:
                try:
                    import cfnresponse
                    physical_id = generate_physical_id(event['StackId'], event['LogicalResourceId'])
                    cfnresponse.send(event, context, cfnresponse.SUCCESS, response_data, physical_id)
                except ImportError:
                    logger.warning("cfnresponse not available, returning direct response")

            return response_data

    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        error_response = {
            'Error': str(e),
            'Status': 'FAILED'
        }

        # For CloudFormation compatibility
        if 'StackId' in event:
            try:
                import cfnresponse
                physical_id = generate_physical_id(event['StackId'], event['LogicalResourceId'])
                cfnresponse.send(event, context, cfnresponse.FAILED, error_response, physical_id, reason=str(e))
                return error_response
            except ImportError:
                logger.warning("cfnresponse not available, returning direct error response")
                return error_response
        else:
            raise

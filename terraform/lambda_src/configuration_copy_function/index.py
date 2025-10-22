# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import boto3
import json
import logging
import traceback
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def send_cfn_response(event, context, response_status, response_data, physical_resource_id=None, reason=None):
    """
    Send CloudFormation custom resource response.

    Args:
        event: Lambda event containing ResponseURL
        context: Lambda context
        response_status: 'SUCCESS' or 'FAILED'
        response_data: Dict of response data
        physical_resource_id: Optional physical resource ID
        reason: Optional failure reason
    """
    response_url = event.get('ResponseURL')
    if not response_url:
        logger.warning("No ResponseURL in event - skipping CFN response")
        return

    # Build response body
    response_body = {
        'Status': response_status,
        'Reason': reason or f"See CloudWatch Log Stream: {context.log_stream_name}",
        'PhysicalResourceId': physical_resource_id or context.log_stream_name,
        'StackId': event.get('StackId', ''),
        'RequestId': event.get('RequestId', ''),
        'LogicalResourceId': event.get('LogicalResourceId', ''),
        'Data': response_data
    }

    json_response_body = json.dumps(response_body)
    logger.info(f"Sending CFN response: {json_response_body}")

    headers = {
        'content-type': '',
        'content-length': str(len(json_response_body))
    }

    try:
        request = Request(response_url, data=json_response_body.encode('utf-8'), headers=headers, method='PUT')
        with urlopen(request) as response:
            logger.info(f"CFN response sent successfully: {response.status}")
    except (HTTPError, URLError) as e:
        logger.error(f"Failed to send CFN response: {e}")
        raise

def handler(event, context):
    """
    Lambda handler for copying configuration files from source to target S3 bucket.

    Supports two invocation modes:
    1. CloudFormation Custom Resource: Sends response to ResponseURL
    2. Direct Terraform Lambda Invocation: Returns JSON response

    Required ResourceProperties:
    - SourceBucket: Source S3 bucket name
    - SourcePrefix: Prefix path in source bucket
    - TargetBucket: Target S3 bucket name
    - FileList: List of file paths to copy (required, must be array)

    Optional ResourceProperties:
    - TargetPrefix: Prefix path in target bucket
    - SSECustomerKey: Customer-provided encryption key
    - ServerSideEncryption: Server-side encryption type (AES256, aws:kms)
    - SSEKMSKeyId: KMS key ID for encryption
    """
    logger.info(f"Received event: {json.dumps(event)}")

    # Check if this is a CloudFormation custom resource invocation
    is_cfn = 'ResponseURL' in event

    if is_cfn:
        logger.info("CloudFormation custom resource mode detected")

    try:
        # Validate RequestType is present
        request_type = event.get('RequestType')
        if not request_type:
            error_msg = "Missing required field 'RequestType' in event. Must be 'Create', 'Update', or 'Delete'."
            logger.error(error_msg)

            if is_cfn:
                send_cfn_response(event, context, 'FAILED', {}, reason=error_msg)
                return

            return {
                'statusCode': 400,
                'body': json.dumps({'error': error_msg})
            }

        logger.info(f"Processing RequestType: {request_type}")

        # Fetch ResourceProperties and validate required keys
        resource_props = event.get('ResourceProperties', {})
        required_keys = ['SourceBucket', 'SourcePrefix', 'TargetBucket', 'FileList']
        missing_keys = [key for key in required_keys if key not in resource_props]

        if missing_keys:
            error_msg = f"Missing required ResourceProperties: {', '.join(missing_keys)}"
            logger.error(error_msg)

            if is_cfn:
                send_cfn_response(event, context, 'FAILED', {}, reason=error_msg)
                return

            return {
                'statusCode': 400,
                'body': json.dumps({'error': error_msg})
            }

        # Validate FileList is a list
        file_list = resource_props.get('FileList', [])
        if not isinstance(file_list, list):
            error_msg = f"FileList must be a list, got {type(file_list).__name__}"
            logger.error(error_msg)

            if is_cfn:
                send_cfn_response(event, context, 'FAILED', {}, reason=error_msg)
                return

            return {
                'statusCode': 400,
                'body': json.dumps({'error': error_msg})
            }

        # Assign validated properties
        source_bucket = resource_props['SourceBucket']
        source_prefix = resource_props['SourcePrefix'].strip().rstrip('/')
        target_bucket = resource_props['TargetBucket']
        target_prefix = resource_props.get('TargetPrefix', '').strip().rstrip('/')

        # Optional encryption properties
        sse_customer_key = resource_props.get('SSECustomerKey')
        server_side_encryption = resource_props.get('ServerSideEncryption')
        sse_kms_key_id = resource_props.get('SSEKMSKeyId')

        s3_client = boto3.client('s3')

        if request_type in ('Create', 'Update'):
            # Copy files explicitly from the provided list
            copied_count = 0
            failed_copies = []

            for relative_file_path in file_list:
                # Normalize and skip empty entries
                relative_file_path = relative_file_path.strip()
                if not relative_file_path:
                    continue

                # Remove leading slashes to prevent double slashes
                relative_file_path = relative_file_path.lstrip('/')

                # Build S3 keys with safe joining (avoid double slashes)
                if source_prefix:
                    source_key = f"{source_prefix}/{relative_file_path}"
                else:
                    source_key = relative_file_path

                if target_prefix:
                    target_key = f"{target_prefix}/{relative_file_path}"
                else:
                    target_key = relative_file_path

                logger.info(f"Copying s3://{source_bucket}/{source_key} to s3://{target_bucket}/{target_key}")

                try:
                    copy_source = {'Bucket': source_bucket, 'Key': source_key}

                    # Build copy_object parameters with optional encryption
                    copy_params = {
                        'CopySource': copy_source,
                        'Bucket': target_bucket,
                        'Key': target_key
                    }

                    # Add encryption parameters if provided
                    if sse_customer_key:
                        copy_params['SSECustomerKey'] = sse_customer_key
                    if server_side_encryption:
                        copy_params['ServerSideEncryption'] = server_side_encryption
                    if sse_kms_key_id:
                        copy_params['SSEKMSKeyId'] = sse_kms_key_id

                    s3_client.copy_object(**copy_params)
                    copied_count += 1
                    logger.info(f"Successfully copied {source_key}")

                except Exception as copy_error:
                    error_details = {
                        'key': source_key,
                        'error': str(copy_error),
                        'traceback': traceback.format_exc()
                    }
                    failed_copies.append(error_details)
                    logger.error(f"Failed to copy {source_key}: {str(copy_error)}\n{traceback.format_exc()}")
                    # Continue with other files to get complete failure list

            # Build response data
            response_data = {
                'CopiedFiles': copied_count,
                'FailedFiles': len(failed_copies),
                'TotalFiles': len([f for f in file_list if f.strip()])
            }

            # Check if operation was successful
            if copied_count == 0 and len(file_list) > 0:
                # Build detailed error message with all failures (truncated for logs)
                failed_keys = [f['key'] for f in failed_copies]
                error_summary = '; '.join([f"{f['key']}: {f['error']}" for f in failed_copies[:3]])  # First 3 errors
                if len(failed_copies) > 3:
                    error_summary += f" ... and {len(failed_copies) - 3} more errors"

                error_msg = (
                    f"Failed to copy any configuration files. "
                    f"Failed keys: {', '.join(failed_keys[:5])}{'...' if len(failed_keys) > 5 else ''}. "
                    f"Errors: {error_summary}"
                )
                logger.error(f"Complete failure: {error_msg}")

                if is_cfn:
                    send_cfn_response(event, context, 'FAILED', response_data, reason=error_msg[:1024])
                    return

                return {
                    'statusCode': 500,
                    'body': json.dumps({'error': error_msg[:512], **response_data})
                }

            # Success case: at least one file copied
            success_msg = f"Successfully copied {copied_count}/{response_data['TotalFiles']} configuration files"
            logger.info(success_msg)

            if failed_copies:
                warning_msg = f"{len(failed_copies)} files failed to copy"
                logger.warning(warning_msg)
                response_data['warning'] = warning_msg

            response_data['message'] = success_msg

            if is_cfn:
                send_cfn_response(event, context, 'SUCCESS', response_data)
                return

            return {
                'statusCode': 200,
                'body': json.dumps(response_data)
            }

        elif request_type == 'Delete':
            # For delete, we don't need to clean up the configuration files
            # as they may be needed by other resources
            logger.info("Delete request - no action needed for configuration files")
            response_data = {'message': "Delete completed - configuration files retained"}

            if is_cfn:
                send_cfn_response(event, context, 'SUCCESS', response_data)
                return

            return {
                'statusCode': 200,
                'body': json.dumps(response_data)
            }

        else:
            # Unknown RequestType
            error_msg = f"Unknown RequestType '{request_type}'. Must be 'Create', 'Update', or 'Delete'."
            logger.error(error_msg)

            if is_cfn:
                send_cfn_response(event, context, 'FAILED', {}, reason=error_msg)
                return

            return {
                'statusCode': 400,
                'body': json.dumps({'error': error_msg})
            }

    except Exception as e:
        error_msg = f"Error copying configuration files: {str(e)}"
        error_trace = traceback.format_exc()
        logger.error(f"{error_msg}\n{error_trace}")

        if is_cfn:
            send_cfn_response(event, context, 'FAILED', {}, reason=f"{error_msg[:1000]}")
            return

        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_msg,
                'details': error_trace[:512]  # Truncated stack trace
            })
        }

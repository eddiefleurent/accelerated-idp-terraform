# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import boto3
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """
    Lambda handler for copying configuration files from source to target S3 bucket.
    Works with direct Lambda invocation (Terraform) and CloudFormation custom resources.
    """
    logger.info(json.dumps(event))

    try:
        # Fetch ResourceProperties once and validate required keys
        resource_props = event.get('ResourceProperties', {})
        required_keys = ['SourceBucket', 'SourcePrefix', 'TargetBucket']
        missing_keys = [key for key in required_keys if key not in resource_props]

        if missing_keys:
            error_msg = f"Missing required ResourceProperties: {', '.join(missing_keys)}"
            logger.error(error_msg)
            return {
                'statusCode': 400,
                'body': json.dumps({'error': error_msg})
            }

        # Now safely assign validated properties
        source_bucket = resource_props['SourceBucket']
        source_prefix = resource_props['SourcePrefix']
        target_bucket = resource_props['TargetBucket']
        target_prefix = resource_props.get('TargetPrefix', '')
        file_list = resource_props.get('FileList', [])

        s3_client = boto3.client('s3')

        if event.get('RequestType') in ('Create', 'Update'):
            # Copy files explicitly from the provided list
            copied_count = 0
            failed_copies = []

            for relative_file_path in file_list:
                # Skip empty entries
                if not relative_file_path.strip():
                    continue

                # Construct source key
                source_key = f"{source_prefix}/{relative_file_path}"

                # Construct target key with optional target prefix
                if target_prefix:
                    target_key = f"{target_prefix}/{relative_file_path}"
                else:
                    target_key = relative_file_path

                logger.info(f"Copying {source_bucket}/{source_key} to {target_bucket}/{target_key}")

                try:
                    copy_source = {'Bucket': source_bucket, 'Key': source_key}
                    s3_client.copy_object(
                        CopySource=copy_source,
                        Bucket=target_bucket,
                        Key=target_key
                    )
                    copied_count += 1
                except Exception as copy_error:
                    error_details = {
                        'key': source_key,
                        'error': str(copy_error)
                    }
                    failed_copies.append(error_details)
                    logger.warning(f"Failed to copy {source_key}: {str(copy_error)}")
                    # Continue with other files to get complete failure list

            # Enforce minimum success threshold: at least one file must be copied
            if copied_count == 0 and len(file_list) > 0:
                # Build detailed error message with all failures
                failed_keys = [f['key'] for f in failed_copies]
                error_summary = '; '.join([f"{f['key']}: {f['error']}" for f in failed_copies])
                error_msg = (
                    f"Failed to copy any configuration files. "
                    f"Failed keys: {', '.join(failed_keys)}. "
                    f"Errors: {error_summary}"
                )
                logger.error(error_msg)
                return {
                    'statusCode': 500,
                    'body': json.dumps({'error': error_msg[:256]})
                }

            # Success case: at least one file copied
            logger.info(f"Successfully copied {copied_count} configuration files")
            if failed_copies:
                logger.warning(f"{len(failed_copies)} files failed to copy")

            return {
                'statusCode': 200,
                'body': json.dumps({
                    'CopiedFiles': copied_count,
                    'FailedFiles': len(failed_copies),
                    'message': f"Successfully copied {copied_count} configuration files"
                })
            }

        elif event.get('RequestType') == 'Delete':
            # For delete, we don't need to clean up the configuration files
            # as they may be needed by other resources
            logger.info("Delete request - no action needed for configuration files")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': "Delete completed - configuration files retained"
                })
            }

    except Exception as e:
        logger.error(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f"Error copying configuration files: {str(e)}"
            })
        }

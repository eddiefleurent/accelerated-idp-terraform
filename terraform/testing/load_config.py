#!/usr/bin/env python3
"""
Load Pattern 2 configuration from YAML file into DynamoDB.
Converts YAML to DynamoDB-compatible JSON format.
"""

import json
import sys
import yaml
import boto3
from decimal import Decimal
import math


def convert_to_dynamodb_format(obj):
    """
    Convert Python objects to DynamoDB format.
    Handles nested structures, numbers, strings, lists, etc.
    """
    if obj is None:
        return {"NULL": True}
    elif isinstance(obj, bool):
        return {"BOOL": obj}
    elif isinstance(obj, str):
        return {"S": obj}
    elif isinstance(obj, (int, float, Decimal)):
        # DynamoDB does not accept NaN/Infinity; stringify via Decimal for precision.
        if isinstance(obj, float) and (math.isnan(obj) or math.isinf(obj)):
            raise ValueError("NaN/Infinity are not supported for DynamoDB Number attributes")
        return {"N": str(Decimal(str(obj)))}
    elif isinstance(obj, list):
        return {"L": [convert_to_dynamodb_format(item) for item in obj]}
    elif isinstance(obj, dict):
        return {"M": {k: convert_to_dynamodb_format(v) for k, v in obj.items()}}
    else:
        return {"S": str(obj)}


def load_config_to_dynamodb(yaml_file_path, table_name, region, config_id="Default"):
    """
    Load configuration from YAML file into DynamoDB table.
    """
    print(f"Loading configuration from: {yaml_file_path}")

    # Read YAML file
    with open(yaml_file_path, 'r') as f:
        config_data = yaml.safe_load(f)

    if not isinstance(config_data, dict) or len(config_data) == 0:
        print("✗ YAML must contain a top-level mapping with at least one key.")
        return False
    print(f"Parsed YAML with {len(config_data)} top-level keys")

    # Convert to DynamoDB format
    dynamodb_item = {
        "Configuration": {"S": config_id}
    }

    # Add all configuration fields
    for key, value in config_data.items():
        dynamodb_item[key] = convert_to_dynamodb_format(value)

    print(f"Converted to DynamoDB format with {len(dynamodb_item)} fields")

    # Put item into DynamoDB
    client = boto3.client('dynamodb', region_name=region)

    print(f"Inserting into DynamoDB table: {table_name}")
    print(f"Region: {region}")
    print(f"Config ID: {config_id}")

    try:
        response = client.put_item(
            TableName=table_name,
            Item=dynamodb_item
        )
        print("✓ Configuration loaded successfully!")
        print(f"Response: {response['ResponseMetadata']['HTTPStatusCode']}")
        return True
    except Exception as e:
        print(f"✗ Error loading configuration: {e}")
        return False


def main():
    if len(sys.argv) < 4:
        print("Usage: python load_config.py <yaml_file> <table_name> <region> [config_id]")
        print("Example: python load_config.py config.yaml genai-idp-test-west-ConfigurationTable us-west-2")
        sys.exit(1)

    yaml_file = sys.argv[1]
    table_name = sys.argv[2]
    region = sys.argv[3]
    config_id = sys.argv[4] if len(sys.argv) > 4 else "Default"

    success = load_config_to_dynamodb(yaml_file, table_name, region, config_id)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()

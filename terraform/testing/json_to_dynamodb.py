"""
Convert regular JSON to DynamoDB JSON format.
"""

import json
import sys
from decimal import Decimal
from typing import Dict, Any, Optional


def to_dynamodb_format(obj):
    """Convert Python object to DynamoDB JSON format"""
    if obj is None:
        return {"NULL": True}
    elif isinstance(obj, bool):
        return {"BOOL": obj}
    elif isinstance(obj, str):
        return {"S": obj}
    elif isinstance(obj, (int, float, Decimal)):
        return {"N": str(obj)}
    elif isinstance(obj, list):
        return {"L": [to_dynamodb_format(item) for item in obj]}
    elif isinstance(obj, dict):
        return {"M": {k: to_dynamodb_format(v) for k, v in obj.items()}}
    else:
        return {"S": str(obj)}


def main():
    if len(sys.argv) < 2:
        print("Usage: python json_to_dynamodb.py <input_json_file> [config_id]")
        sys.exit(1)

    input_file = sys.argv[1]
    config_id = sys.argv[2] if len(sys.argv) > 2 else "Default"

    # Read regular JSON
    with open(input_file, 'r') as f:
        # Preserve numeric precision for DynamoDB "N" by using Decimal
        data = json.load(f, parse_float=Decimal, parse_int=Decimal)

    # Validate input structure
    if not isinstance(data, dict):
        print("Error: top-level JSON must be an object with key/value pairs.", file=sys.stderr)
        sys.exit(2)

    # Convert to DynamoDB format
    dynamodb_item = {
        "Configuration": {"S": config_id}
    }

    for key, value in data.items():
        # Reserve the partition key
        if key == "Configuration":
            continue
        dynamodb_item[key] = to_dynamodb_format(value)

    # Output DynamoDB JSON
    print(json.dumps(dynamodb_item, indent=2))


if __name__ == "__main__":
    main()

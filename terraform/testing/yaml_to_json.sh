#!/bin/bash
# Convert YAML configuration file to standard JSON format.
# Output is printed to stdout and can be piped to other tools.
#
# To load configuration into DynamoDB, use one of these methods:
#   1. Use load_config.py directly (recommended):
#      python3 load_config.py <yaml_file> <table_name> <region> [config_id]
#
#   2. Convert to JSON first, then use json_to_dynamodb.py for DynamoDB format:
#      ./yaml_to_json.sh config.yaml > config.json
#      python3 json_to_dynamodb.py config.json Default > dynamodb.json
#      aws dynamodb put-item --table-name MyTable --item file://dynamodb.json

set -e

YAML_FILE="${1}"

if [ $# -eq 0 ]; then
    echo "Usage: $0 <yaml_file>" >&2
    echo "" >&2
    echo "Converts YAML to JSON and prints to stdout." >&2
    echo "" >&2
    echo "Examples:" >&2
    echo "  # Convert and view JSON:" >&2
    echo "  $0 config.yaml" >&2
    echo "" >&2
    echo "  # Save to file:" >&2
    echo "  $0 config.yaml > config.json" >&2
    echo "" >&2
    echo "To load into DynamoDB, use load_config.py instead:" >&2
    echo "  python3 load_config.py config.yaml <table_name> <region>" >&2
    exit 1
fi

# Convert YAML to JSON using Python
python3 - "$YAML_FILE" << 'PYEOF'
import sys
import json

# Import yaml at module level for early error detection
try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not installed", file=sys.stderr)
    print("Please install: pip install pyyaml", file=sys.stderr)
    sys.exit(1)

def yaml_to_json(yaml_file):
    """Simple YAML to JSON converter for config file"""
    try:
        with open(yaml_file, 'r') as f:
            data = yaml.safe_load(f)
            return json.dumps(data, indent=2)
    except Exception as e:
        print(f"ERROR: Failed to parse YAML file '{yaml_file}': {e}", file=sys.stderr)
        sys.exit(1)

yaml_file = sys.argv[1]
output = yaml_to_json(yaml_file)
print(output)
PYEOF

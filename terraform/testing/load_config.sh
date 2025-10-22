#!/bin/bash
# Load Pattern 2 configuration from YAML file into DynamoDB using AWS CLI

set -e

YAML_FILE="${1:-../../config_library/pattern-2/lending-package-sample/config.yaml}"
TABLE_NAME="${2:-genai-idp-test-west-ConfigurationTable}"
REGION="${3:-us-west-2}"
CONFIG_ID="${4:-Default}"

echo "Loading configuration into DynamoDB..."
echo "YAML File: $YAML_FILE"
echo "Table: $TABLE_NAME"
echo "Region: $REGION"
echo "Config ID: $CONFIG_ID"
echo ""

# Convert YAML to JSON using Python
echo "Converting YAML to JSON..."
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

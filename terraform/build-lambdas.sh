#!/bin/bash
# build-lambdas.sh - Build Lambda functions with dependencies for Terraform deployment
#
# This script builds Lambda function packages with all dependencies installed,
# similar to SAM's `sam build` but for Terraform deployments.
#
# Usage:
#   ./build-lambdas.sh [function_name]
#
# Examples:
#   ./build-lambdas.sh                    # Build all functions
#   ./build-lambdas.sh ocr_function       # Build specific function

set -Eeuo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
BUILD_DIR="${SCRIPT_DIR}/lambda_builds"
PACKAGES_DIR="${SCRIPT_DIR}/lambda_packages"

# Lambda functions to build
declare -A LAMBDA_FUNCTIONS

# Pattern 2 Lambda functions
LAMBDA_FUNCTIONS["ocr_function"]="${PROJECT_ROOT}/patterns/pattern-2/src/ocr_function"
LAMBDA_FUNCTIONS["classification_function"]="${PROJECT_ROOT}/patterns/pattern-2/src/classification_function"
LAMBDA_FUNCTIONS["extraction_function"]="${PROJECT_ROOT}/patterns/pattern-2/src/extraction_function"
LAMBDA_FUNCTIONS["assessment_function"]="${PROJECT_ROOT}/patterns/pattern-2/src/assessment_function"
LAMBDA_FUNCTIONS["pattern2_process_results_function"]="${PROJECT_ROOT}/patterns/pattern-2/src/process-results-function"
LAMBDA_FUNCTIONS["pattern2_hitl_wait_function"]="${PROJECT_ROOT}/patterns/pattern-2/src/hitl-wait-function"
LAMBDA_FUNCTIONS["pattern2_hitl_status_update_function"]="${PROJECT_ROOT}/patterns/pattern-2/src/hitl-status-update-function"
LAMBDA_FUNCTIONS["pattern2_hitl_process_function"]="${PROJECT_ROOT}/patterns/pattern-2/src/hitl-process-function"
LAMBDA_FUNCTIONS["pattern2_summarization_function"]="${PROJECT_ROOT}/patterns/pattern-2/src/summarization_function"

# Shared Lambda functions
LAMBDA_FUNCTIONS["queue_processor_function"]="${PROJECT_ROOT}/src/lambda/queue_processor"
LAMBDA_FUNCTIONS["queue_sender_function"]="${PROJECT_ROOT}/src/lambda/queue_sender"
LAMBDA_FUNCTIONS["workflow_tracker_function"]="${PROJECT_ROOT}/src/lambda/workflow_tracker"
LAMBDA_FUNCTIONS["evaluation_function"]="${PROJECT_ROOT}/src/lambda/evaluation_function"
LAMBDA_FUNCTIONS["save_reporting_data"]="${PROJECT_ROOT}/src/lambda/save_reporting_data"
LAMBDA_FUNCTIONS["lookup_function"]="${PROJECT_ROOT}/src/lambda/lookup_function"
LAMBDA_FUNCTIONS["update_configuration_function"]="${PROJECT_ROOT}/src/lambda/update_configuration"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        Lambda Function Builder for Terraform              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to build a single Lambda function
build_function() {
    local func_name=$1
    local source_dir=$2

    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Building: ${func_name}${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Check if source directory exists
    if [ ! -d "$source_dir" ]; then
        echo -e "${RED}❌ Source directory not found: $source_dir${NC}"
        return 1
    fi

    # Create build directory for this function
    local func_build_dir="${BUILD_DIR}/${func_name}"
    rm -rf "$func_build_dir"
    mkdir -p "$func_build_dir"

    echo -e "${BLUE}📁 Source: ${source_dir}${NC}"
    echo -e "${BLUE}📦 Build:  ${func_build_dir}${NC}"

    # Skip installing dependencies - they come from Lambda layer
    echo -e "${BLUE}ℹ️  Skipping dependencies (will use Lambda layer)${NC}"

    # Copy source files
    echo -e "${YELLOW}📄 Copying source files...${NC}"

    # Copy all Python files, JSON files, and subdirectories recursively
    # Use rsync if available (preserves structure and permissions), otherwise fallback to tar
    if command -v rsync &> /dev/null; then
        echo -e "${BLUE}ℹ️  Using rsync for portable file copying${NC}"
        if ! rsync -av \
            --include='*/' \
            --include='*.py' \
            --include='*.pyc' \
            --include='*.json' \
            --exclude='*' \
            "$source_dir/" "$func_build_dir/"; then
            echo -e "${RED}❌ Error: rsync failed to copy files from ${source_dir}${NC}"
            return 1
        fi
    else
        # Fallback: use portable tar-based copy (works on BSD and GNU systems)
        echo -e "${BLUE}ℹ️  rsync not available, using portable tar-based copy${NC}"

        # Create archive of desired files and extract to destination
        # This approach preserves directory structure and works on all POSIX systems
        if ! (cd "$source_dir" && find . \( -name "*.py" -o -name "*.json" \) -print0 | tar -czf - --null -T - | tar -xzf - -C "$func_build_dir"); then
            echo -e "${RED}❌ Error: tar-based copy failed from ${source_dir}${NC}"
            echo -e "${RED}   This may indicate missing files or tar command issues${NC}"
            return 1
        fi
    fi

    # Count files
    local file_count=$(find "$func_build_dir" -type f | wc -l)
    echo -e "${GREEN}✓ Copied source files (${file_count} total files)${NC}"

    # Create ZIP package
    local zip_file="${PACKAGES_DIR}/${func_name}.zip"
    echo -e "${YELLOW}🗜️  Creating package: ${zip_file}${NC}"

    mkdir -p "$PACKAGES_DIR"

    cd "$func_build_dir"
    zip -qr "$zip_file" . > /dev/null
    cd - > /dev/null

    # Get package size
    local size=$(du -h "$zip_file" | cut -f1)
    echo -e "${GREEN}✓ Package created: ${size}${NC}"

    # Cleanup build directory
    rm -rf "$func_build_dir"

    echo -e "${GREEN}✅ Successfully built ${func_name}${NC}"
    echo ""
}

# Main execution
main() {
    local specific_function=$1

    # Create directories
    mkdir -p "$BUILD_DIR"
    mkdir -p "$PACKAGES_DIR"

    # Python not required (dependencies come from Lambda layer)
    echo -e "${BLUE}Build directory: ${BUILD_DIR}${NC}"
    echo -e "${BLUE}Packages directory: ${PACKAGES_DIR}${NC}"
    echo ""

    # Check required tools
    if ! command -v zip &> /dev/null; then
        echo -e "${RED}❌ zip command not found. Please install zip.${NC}"
        exit 1
    fi

    local total_functions=0
    local successful_builds=0
    local failed_builds=0

    # Build functions
    if [ -n "$specific_function" ]; then
        # Build specific function
        if [ -z "${LAMBDA_FUNCTIONS[$specific_function]:-}" ]; then
            echo -e "${RED}❌ Unknown function: $specific_function${NC}"
            echo -e "${YELLOW}Available functions:${NC}"
            for func in "${!LAMBDA_FUNCTIONS[@]}"; do
                echo "  - $func"
            done
            exit 1
        fi

        total_functions=1
        if build_function "$specific_function" "${LAMBDA_FUNCTIONS[$specific_function]}"; then
            successful_builds=1
        else
            failed_builds=1
        fi
    else
        # Build all functions
        total_functions=${#LAMBDA_FUNCTIONS[@]}

        # Sort function names for deterministic build order
        for func_name in $(printf "%s\n" "${!LAMBDA_FUNCTIONS[@]}" | sort); do
            if build_function "$func_name" "${LAMBDA_FUNCTIONS[$func_name]}"; then
                ((successful_builds++))
            else
                ((failed_builds++))
            fi
        done
    fi

    # Summary
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Build Summary${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Total functions: ${total_functions}"
    echo -e "${GREEN}Successful: ${successful_builds}${NC}"
    if [ $failed_builds -gt 0 ]; then
        echo -e "${RED}Failed: ${failed_builds}${NC}"
    fi
    echo ""

    # List packages
    echo -e "${YELLOW}📦 Lambda packages:${NC}"

    # Enable nullglob to handle case where no zip files exist
    local original_nullglob=$(shopt -p nullglob || echo "shopt -u nullglob")
    shopt -s nullglob

    # Iterate over zip files robustly (handles spaces in filenames)
    local zip_files=("$PACKAGES_DIR"/*.zip)
    if [ ${#zip_files[@]} -eq 0 ]; then
        echo -e "${YELLOW}  No packages found${NC}"
    else
        for zip_file in "${zip_files[@]}"; do
            # Get human-readable size using stat (works with spaces in filenames)
            local size=$(stat -c %s "$zip_file" 2>/dev/null || stat -f %z "$zip_file" 2>/dev/null)
            local human_size=""

            # Convert to human-readable format
            if [ "$size" -ge 1073741824 ]; then
                human_size=$(awk "BEGIN {printf \"%.1fG\", $size/1073741824}")
            elif [ "$size" -ge 1048576 ]; then
                human_size=$(awk "BEGIN {printf \"%.1fM\", $size/1048576}")
            elif [ "$size" -ge 1024 ]; then
                human_size=$(awk "BEGIN {printf \"%.1fK\", $size/1024}")
            else
                human_size="${size}B"
            fi

            printf "  %-50s %s\n" "$(basename "$zip_file")" "$human_size"
        done
    fi

    # Restore original nullglob setting
    eval "$original_nullglob"

    echo ""
    if [ $failed_builds -eq 0 ]; then
        echo -e "${GREEN}✅ All Lambda functions built successfully!${NC}"
        echo ""
        echo -e "${YELLOW}Next steps:${NC}"
        echo "  1. Run: terraform apply -replace=aws_lambda_function.XXX"
        echo "  2. Or redeploy all: terraform apply -auto-approve"
        exit 0
    else
        echo -e "${RED}❌ Some builds failed. Please check errors above.${NC}"
        exit 1
    fi
}

# Run main
main "$@"

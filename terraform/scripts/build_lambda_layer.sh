#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Build script for IDP Common Lambda Layer
# This creates a Lambda layer containing the idp_common package and its dependencies

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LAYER_DIR="${SCRIPT_DIR}/../lambda_layers"
BUILD_DIR="${LAYER_DIR}/idp_common_layer_build"
OUTPUT_ZIP="${LAYER_DIR}/idp_common_layer.zip"

echo "========================================="
echo "Building IDP Common Lambda Layer"
echo "========================================="
echo "Project root: ${PROJECT_ROOT}"
echo "Build directory: ${BUILD_DIR}"
echo "Output: ${OUTPUT_ZIP}"
echo ""

# Clean previous build
echo "Cleaning previous build..."
rm -rf "${BUILD_DIR}"
rm -f "${OUTPUT_ZIP}"

# Create layer directory structure
echo "Creating layer directory structure..."
mkdir -p "${BUILD_DIR}/python"

# Install idp_common package with ALL extras for Pattern 2
echo "Installing idp_common package with all Pattern 2 dependencies..."
pip install \
    "${PROJECT_ROOT}/lib/idp_common_pkg[ocr,classification,extraction,docs_service,evaluation]" \
    -t "${BUILD_DIR}/python" \
    --upgrade \
    --no-cache-dir

# Install additional dependencies needed by configuration functions
echo "Installing additional configuration dependencies..."
pip install \
    PyYAML==6.0.2 \
    -t "${BUILD_DIR}/python" \
    --upgrade \
    --no-cache-dir

# Remove unnecessary files to reduce layer size
echo "Cleaning up unnecessary files..."
cd "${BUILD_DIR}/python"
find . -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find . -type f -name "*.pyc" -delete
find . -type f -name "*.pyo" -delete
find . -type d -name "*.dist-info" -exec rm -rf {} + 2>/dev/null || true
find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true

# Create ZIP file
echo "Creating layer ZIP file..."
cd "${BUILD_DIR}"
zip -r "${OUTPUT_ZIP}" python/ -q

# Get ZIP size
ZIP_SIZE=$(du -h "${OUTPUT_ZIP}" | cut -f1)
echo ""
echo "========================================="
echo "Lambda layer built successfully!"
echo "Location: ${OUTPUT_ZIP}"
echo "Size: ${ZIP_SIZE}"
echo "========================================="
echo ""
echo "Layer contents:"
echo "- idp_common package (all modules)"
echo "- requests (required for AppSync)"
echo "- boto3 (pinned version)"
echo ""

# Cleanup build directory
echo "Cleaning up build directory..."
rm -rf "${BUILD_DIR}"

echo "Done!"

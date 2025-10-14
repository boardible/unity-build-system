#!/bin/bash

# Quick test script for CSV migration
# Tests downloading a single CSV to verify Google Sheets access

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE} CSV Migration Test${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# Test 1: AWS CLI installed
echo -e "${BLUE}[TEST 1]${NC} Checking AWS CLI..."
if command -v aws &> /dev/null; then
    echo -e "${GREEN}✅ AWS CLI is installed${NC}"
    aws --version
else
    echo -e "${RED}❌ AWS CLI not found${NC}"
    echo -e "${YELLOW}Install with: brew install awscli${NC}"
    exit 1
fi
echo ""

# Test 2: AWS credentials configured
echo -e "${BLUE}[TEST 2]${NC} Checking AWS credentials..."
if aws sts get-caller-identity &> /dev/null; then
    echo -e "${GREEN}✅ AWS credentials configured${NC}"
    aws sts get-caller-identity --output table
else
    echo -e "${RED}❌ AWS credentials not configured${NC}"
    echo -e "${YELLOW}Configure with: aws configure${NC}"
    exit 1
fi
echo ""

# Test 3: S3 bucket access
echo -e "${BLUE}[TEST 3]${NC} Checking S3 bucket access..."
if aws s3 ls s3://boardible-app/ineuj-app/ &> /dev/null; then
    echo -e "${GREEN}✅ S3 bucket is accessible${NC}"
    echo "Contents:"
    aws s3 ls s3://boardible-app/ineuj-app/ | head -5
else
    echo -e "${RED}❌ Cannot access S3 bucket${NC}"
    echo -e "${YELLOW}Verify bucket permissions${NC}"
    exit 1
fi
echo ""

# Test 4: Download test CSV from Google Sheets
echo -e "${BLUE}[TEST 4]${NC} Testing Google Sheets CSV download..."
TEST_URL="https://docs.google.com/spreadsheets/d/e/2PACX-1vTCK2X4TleXQco9-_u_pdbT1HAiR0sgRqxvyrcUgVApHqTLz3fDQUWTnTNdEyuI0jQCf_MEjpKn-rTV/pub?gid=0&single=true&output=csv"
TEST_FILE="/tmp/test-csv-download.csv"

if curl -sSL -o "$TEST_FILE" "$TEST_URL"; then
    if [ -s "$TEST_FILE" ]; then
        LINE_COUNT=$(wc -l < "$TEST_FILE")
        echo -e "${GREEN}✅ Successfully downloaded test CSV${NC}"
        echo "   Lines: $LINE_COUNT"
        echo "   First 3 lines:"
        head -3 "$TEST_FILE" | sed 's/^/   /'
        rm "$TEST_FILE"
    else
        echo -e "${RED}❌ Downloaded CSV is empty${NC}"
        exit 1
    fi
else
    echo -e "${RED}❌ Failed to download CSV from Google Sheets${NC}"
    echo -e "${YELLOW}Check if spreadsheet is published${NC}"
    exit 1
fi
echo ""

# Test 5: Check if CloudFront distribution ID exists
echo -e "${BLUE}[TEST 5]${NC} Checking CloudFront configuration..."
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_PATH="$(dirname "$SCRIPT_DIR")"
AWS_CONFIG="$PROJECT_PATH/AWSDevInfos.asset"

if [ -f "$AWS_CONFIG" ]; then
    DIST_ID=$(grep -o '"distributionID":"[^"]*"' "$AWS_CONFIG" | cut -d'"' -f4)
    if [ -n "$DIST_ID" ]; then
        echo -e "${GREEN}✅ CloudFront distribution configured${NC}"
        echo "   Distribution ID: $DIST_ID"
    else
        echo -e "${YELLOW}⚠️  CloudFront distribution ID not found${NC}"
        echo "   Cache invalidation will be skipped"
    fi
else
    echo -e "${YELLOW}⚠️  AWSDevInfos.asset not found${NC}"
    echo "   Expected: $AWS_CONFIG"
fi
echo ""

# Summary
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE} Test Summary${NC}"
echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}✅ All critical tests passed!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Run full sync: ./Scripts/sync-csv-to-s3.sh dev"
echo "2. Test in Unity with dev CSVs"
echo "3. Sync to prod when ready: ./Scripts/sync-csv-to-s3.sh prod"
echo ""

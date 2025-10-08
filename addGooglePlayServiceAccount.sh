#!/bin/bash

# Google Play Service Account JSON Importer
# This script helps you safely add your service account JSON to .env.android.local

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Google Play Service Account JSON Importer ===${NC}"
echo ""

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
ENV_FILE="$SCRIPT_DIR/.env.android.local"

if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}Error: .env.android.local not found at $ENV_FILE${NC}"
    exit 1
fi

echo "This script will help you add your Google Play Service Account JSON to .env.android.local"
echo ""
echo -e "${YELLOW}You should have downloaded a JSON file from Google Cloud Console${NC}"
echo "It looks like: your-project-123456-abc123.json"
echo ""

# Prompt for JSON file path
read -p "Enter the path to your JSON file (or drag it here): " JSON_PATH

# Remove quotes if user dragged the file
JSON_PATH=$(echo "$JSON_PATH" | sed "s/['\"]//g")

# Expand tilde
JSON_PATH="${JSON_PATH/#\~/$HOME}"

if [ ! -f "$JSON_PATH" ]; then
    echo -e "${RED}Error: File not found: $JSON_PATH${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}Validating JSON file...${NC}"

# Validate it's proper JSON
if ! python3 -m json.tool "$JSON_PATH" > /dev/null 2>&1; then
    echo -e "${RED}Error: File is not valid JSON${NC}"
    exit 1
fi

# Check if it has required fields
if ! grep -q '"type": "service_account"' "$JSON_PATH"; then
    echo -e "${RED}Error: This doesn't look like a service account JSON${NC}"
    echo "Make sure you downloaded the JSON key from Google Cloud Console"
    exit 1
fi

echo -e "${GREEN}✅ JSON file is valid${NC}"
echo ""

# Extract some info to show user
PROJECT_ID=$(python3 -c "import json; print(json.load(open('$JSON_PATH'))['project_id'])" 2>/dev/null || echo "unknown")
CLIENT_EMAIL=$(python3 -c "import json; print(json.load(open('$JSON_PATH'))['client_email'])" 2>/dev/null || echo "unknown")

echo -e "${BLUE}Service Account Information:${NC}"
echo "  Project ID: $PROJECT_ID"
echo "  Client Email: $CLIENT_EMAIL"
echo ""

# Read JSON content (minified for single line)
JSON_CONTENT=$(python3 -c "import json; print(json.dumps(json.load(open('$JSON_PATH'))))")

echo -e "${YELLOW}⚠️  WARNING: This will replace the current GOOGLE_PLAY_SERVICE_ACCOUNT_JSON in your .env file${NC}"
read -p "Continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

# Create backup
cp "$ENV_FILE" "$ENV_FILE.backup"
echo -e "${GREEN}✅ Created backup: $ENV_FILE.backup${NC}"

# Create temp file with new JSON
TEMP_FILE=$(mktemp)

# Read current .env, replace the JSON section
python3 << EOF
import re
import json

# Read current .env file
with open('$ENV_FILE', 'r') as f:
    content = f.read()

# Load and format JSON properly
with open('$JSON_PATH', 'r') as f:
    json_data = json.load(f)

# Format as single-line JSON for the .env file
json_str = json.dumps(json_data)

# Replace the GOOGLE_PLAY_SERVICE_ACCOUNT_JSON section
pattern = r'export GOOGLE_PLAY_SERVICE_ACCOUNT_JSON=\{[^}]*\}'
replacement = f"export GOOGLE_PLAY_SERVICE_ACCOUNT_JSON='{json_str}'"

new_content = re.sub(pattern, replacement, content, flags=re.DOTALL)

# Write to temp file
with open('$TEMP_FILE', 'w') as f:
    f.write(new_content)

print("JSON updated successfully")
EOF

# Replace original file
mv "$TEMP_FILE" "$ENV_FILE"

echo ""
echo -e "${GREEN}✅ Successfully updated $ENV_FILE${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Verify the file looks correct:"
echo "   cat $ENV_FILE"
echo ""
echo "2. Test that it loads properly:"
echo "   source $ENV_FILE"
echo "   echo \$GOOGLE_PLAY_SERVICE_ACCOUNT_JSON | python3 -m json.tool"
echo ""
echo "3. You can now deploy to Google Play:"
echo "   ./Scripts/androidDeploy.sh"
echo ""
echo -e "${YELLOW}🔒 Security Reminder:${NC}"
echo "  - NEVER commit .env.android.local to git"
echo "  - Keep your JSON key file in a secure location"
echo "  - Rotate keys periodically for security"
echo ""

# Optional: Delete the JSON file after import
read -p "Do you want to delete the JSON file now that it's imported? (yes/no): " DELETE_JSON
if [ "$DELETE_JSON" = "yes" ]; then
    rm "$JSON_PATH"
    echo -e "${GREEN}✅ Deleted $JSON_PATH${NC}"
    echo "The credentials are now only in your .env.android.local file"
fi

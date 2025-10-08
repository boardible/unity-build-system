#!/bin/bash

# Sync GitHub Secrets to Local Environment
# This script helps you copy secrets from GitHub to your local .env files
# Requires: gh CLI (GitHub CLI tool) - install with: brew install gh

set -e

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_PATH="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== GitHub Secrets to Local Environment Sync ===${NC}"
echo ""

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo -e "${RED}Error: GitHub CLI (gh) is not installed${NC}"
    echo ""
    echo "Install it with:"
    echo "  brew install gh"
    echo ""
    echo "Then authenticate with:"
    echo "  gh auth login"
    exit 1
fi

# Check if authenticated
if ! gh auth status &> /dev/null; then
    echo -e "${RED}Error: Not authenticated with GitHub CLI${NC}"
    echo ""
    echo "Run: gh auth login"
    exit 1
fi

# Function to get secret from GitHub
get_github_secret() {
    local secret_name="$1"
    local repo="${2:-boardible/ineuj}"
    
    # Note: GitHub CLI cannot directly read secret values for security reasons
    # This function is a placeholder to show the structure
    echo -e "${YELLOW}⚠️  Cannot read secret value: $secret_name${NC}"
    echo "   GitHub does not allow reading secret values via API (by design)"
    return 1
}

echo -e "${YELLOW}📋 Important Information:${NC}"
echo ""
echo "GitHub Secrets are write-only by design - you cannot read them back via API."
echo "This means you need to manually copy your secrets to your local environment."
echo ""
echo "This script will help you by:"
echo "  1. Showing you what secrets are configured in GitHub"
echo "  2. Guiding you to update your local .env files"
echo ""

# Get repository secrets list
echo -e "${BLUE}Fetching secrets list from GitHub...${NC}"
REPO="boardible/ineuj"

if ! SECRETS_OUTPUT=$(gh secret list --repo "$REPO" 2>&1); then
    echo -e "${RED}Error: Failed to list secrets${NC}"
    echo "$SECRETS_OUTPUT"
    echo ""
    echo "Make sure you have access to the repository: $REPO"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ Secrets configured in GitHub:${NC}"
echo "$SECRETS_OUTPUT"
echo ""

# Ask user what they want to do
echo -e "${YELLOW}What would you like to do?${NC}"
echo "  1. Copy secrets FROM your local .env TO GitHub (recommended for initial setup)"
echo "  2. Manually update local .env with values FROM GitHub (you need the values)"
echo "  3. Show template for both files"
echo "  4. Exit"
echo ""
read -p "Choose [1-4]: " choice

case $choice in
    1)
        echo ""
        echo -e "${BLUE}=== Upload Local Secrets to GitHub ===${NC}"
        echo ""
        
        # Source local env file
        ENV_FILE="$SCRIPT_DIR/.env.android.local"
        if [ ! -f "$ENV_FILE" ]; then
            echo -e "${RED}Error: $ENV_FILE not found${NC}"
            echo "Run: ./Scripts/setupLocalAndroid.sh --create-env"
            exit 1
        fi
        
        # Source the file
        set +e  # Don't exit on error
        source "$ENV_FILE"
        set -e
        
        echo "The following secrets will be uploaded to GitHub:"
        echo ""
        echo "  • FB_APP_ID"
        echo "  • FB_CLIENT_TOKEN"
        echo "  • GOOGLE_PLAY_SERVICE_ACCOUNT_JSON"
        echo "  • ANDROID_PACKAGE_NAME"
        echo "  • ANDROID_KEYSTORE_PASS"
        echo "  • ANDROID_KEY_ALIAS"
        echo "  • ANDROID_KEY_PASS"
        echo ""
        echo -e "${YELLOW}⚠️  You'll also need to upload ANDROID_KEYSTORE_BASE64 separately${NC}"
        echo ""
        read -p "Continue? [y/N]: " confirm
        
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            exit 0
        fi
        
        echo ""
        echo "Uploading secrets..."
        
        # Upload each secret
        if [ -n "$FB_APP_ID" ]; then
            echo -n "  • FB_APP_ID... "
            if gh secret set FB_APP_ID --body "$FB_APP_ID" --repo "$REPO" 2>&1; then
                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${RED}✗${NC}"
            fi
        fi
        
        if [ -n "$FB_CLIENT_TOKEN" ]; then
            echo -n "  • FB_CLIENT_TOKEN... "
            if gh secret set FB_CLIENT_TOKEN --body "$FB_CLIENT_TOKEN" --repo "$REPO" 2>&1; then
                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${RED}✗${NC}"
            fi
        fi
        
        if [ -n "$GOOGLE_PLAY_SERVICE_ACCOUNT_JSON" ]; then
            echo -n "  • GOOGLE_PLAY_SERVICE_ACCOUNT_JSON... "
            if gh secret set GOOGLE_PLAY_SERVICE_ACCOUNT_JSON --body "$GOOGLE_PLAY_SERVICE_ACCOUNT_JSON" --repo "$REPO" 2>&1; then
                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${RED}✗${NC}"
            fi
        fi
        
        if [ -n "$ANDROID_PACKAGE_NAME" ]; then
            echo -n "  • ANDROID_PACKAGE_NAME... "
            if gh secret set ANDROID_PACKAGE_NAME --body "$ANDROID_PACKAGE_NAME" --repo "$REPO" 2>&1; then
                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${RED}✗${NC}"
            fi
        fi
        
        if [ -n "$ANDROID_KEYSTORE_PASS" ]; then
            echo -n "  • ANDROID_KEYSTORE_PASS... "
            if gh secret set ANDROID_KEYSTORE_PASS --body "$ANDROID_KEYSTORE_PASS" --repo "$REPO" 2>&1; then
                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${RED}✗${NC}"
            fi
        fi
        
        if [ -n "$ANDROID_KEY_ALIAS" ]; then
            echo -n "  • ANDROID_KEY_ALIAS... "
            if gh secret set ANDROID_KEY_ALIAS --body "$ANDROID_KEY_ALIAS" --repo "$REPO" 2>&1; then
                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${RED}✗${NC}"
            fi
        fi
        
        if [ -n "$ANDROID_KEY_PASS" ]; then
            echo -n "  • ANDROID_KEY_PASS... "
            if gh secret set ANDROID_KEY_PASS --body "$ANDROID_KEY_PASS" --repo "$REPO" 2>&1; then
                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${RED}✗${NC}"
            fi
        fi
        
        echo ""
        echo -e "${YELLOW}⚠️  Don't forget to upload your Android keystore!${NC}"
        echo ""
        echo "Run this command to encode and upload your keystore:"
        if [ -n "$ANDROID_KEYSTORE_PATH" ]; then
            echo -e "  ${BLUE}base64 -i \"$ANDROID_KEYSTORE_PATH\" | gh secret set ANDROID_KEYSTORE_BASE64 --repo $REPO${NC}"
        else
            echo -e "  ${BLUE}base64 -i /path/to/keystore.jks | gh secret set ANDROID_KEYSTORE_BASE64 --repo $REPO${NC}"
        fi
        echo ""
        echo -e "${GREEN}✓ Secrets uploaded successfully!${NC}"
        ;;
        
    2)
        echo ""
        echo -e "${BLUE}=== Manual Update Guide ===${NC}"
        echo ""
        echo "Since GitHub doesn't allow reading secret values, you need to:"
        echo ""
        echo "1. Go to: https://github.com/$REPO/settings/secrets/actions"
        echo "2. Copy each secret value"
        echo "3. Update your local file: $SCRIPT_DIR/.env.android.local"
        echo ""
        echo "Required secrets:"
        echo "  • FB_APP_ID"
        echo "  • FB_CLIENT_TOKEN"
        echo "  • GOOGLE_PLAY_SERVICE_ACCOUNT_JSON"
        echo "  • ANDROID_PACKAGE_NAME"
        echo "  • ANDROID_KEYSTORE_BASE64 (decode and save to file)"
        echo "  • ANDROID_KEYSTORE_PASS"
        echo "  • ANDROID_KEY_ALIAS"
        echo "  • ANDROID_KEY_PASS"
        echo ""
        ;;
        
    3)
        echo ""
        echo -e "${BLUE}=== Templates ===${NC}"
        echo ""
        echo "📄 Local template: $SCRIPT_DIR/.env.android.local.template"
        echo "📄 CI/CD docs: $SCRIPT_DIR/CI-CD-ENVIRONMENT-VARIABLES.md"
        echo ""
        cat "$SCRIPT_DIR/.env.android.local.template"
        ;;
        
    4)
        echo "Exiting."
        exit 0
        ;;
        
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}✓ Done!${NC}"

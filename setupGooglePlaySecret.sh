#!/bin/bash

# Quick Google Play Service Account JSON Secret Setup
# This is a simplified script specifically for setting up the Google Play JSON secret

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "success") echo -e "${GREEN}✅ $message${NC}" ;;
        "error") echo -e "${RED}❌ $message${NC}" ;;
        "warning") echo -e "${YELLOW}⚠️  $message${NC}" ;;
        "info") echo -e "${BLUE}ℹ️  $message${NC}" ;;
    esac
}

# Function to get repository info
get_repo_info() {
    local repo_url=$(git remote get-url origin 2>/dev/null || echo "")
    if [ -z "$repo_url" ]; then
        print_status "error" "Not in a Git repository or no origin remote found"
        exit 1
    fi
    
    # Extract owner/repo from URL
    if [[ $repo_url =~ github\.com[/:]([^/]+)/([^/]+)(\.git)?$ ]]; then
        REPO_OWNER="${BASH_REMATCH[1]}"
        REPO_NAME="${BASH_REMATCH[2]}"
        REPO_NAME="${REPO_NAME%.git}"  # Remove .git suffix if present
    else
        print_status "error" "Could not parse GitHub repository URL: $repo_url"
        exit 1
    fi
}

main() {
    echo "==============================================="
    echo "🤖 Google Play Service Account JSON Setup"
    echo "==============================================="
    echo ""
    
    # Check if gh CLI is installed and authenticated
    if ! command -v gh &> /dev/null; then
        print_status "error" "GitHub CLI (gh) is not installed"
        echo "Please install it first: https://cli.github.com/"
        exit 1
    fi
    
    if ! gh auth status &> /dev/null; then
        print_status "error" "GitHub CLI is not authenticated"
        echo "Please authenticate with: gh auth login"
        exit 1
    fi
    
    get_repo_info
    print_status "info" "Repository: $REPO_OWNER/$REPO_NAME"
    echo ""
    
    # Prompt for JSON file
    echo "📋 Google Play Service Account JSON Setup"
    echo ""
    echo "You need the service account JSON file from Google Play Console:"
    echo "1. Go to Google Play Console → Setup → API access"
    echo "2. Create or use existing service account"
    echo "3. Download the JSON key file"
    echo ""
    
    read -p "Enter the path to your Google Play service account JSON file: " json_file
    
    if [ ! -f "$json_file" ]; then
        print_status "error" "File not found: $json_file"
        exit 1
    fi
    
    # Validate it's a JSON file
    if ! cat "$json_file" | python3 -m json.tool > /dev/null 2>&1; then
        print_status "error" "Invalid JSON file: $json_file"
        exit 1
    fi
    
    print_status "info" "JSON file validated successfully"
    
    # Set the secret
    cat "$json_file" | gh secret set "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON" --repo "$REPO_OWNER/$REPO_NAME"
    
    print_status "success" "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON secret has been set!"
    echo ""
    print_status "info" "You can now run './Scripts/checkSecrets.sh' to verify all secrets are configured"
}

main "$@"
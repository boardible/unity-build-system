#!/bin/bash

# GitHub Secrets Setup Helper
# This script helps you set up all required secrets for the Unity CI/CD pipeline

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

# Function to prompt for secret value
prompt_secret() {
    local secret_name=$1
    local description=$2
    local is_multiline=$3
    local example=$4
    local allow_file_input=${5:-false}
    
    echo ""
    print_status "info" "Setting up: $secret_name"
    echo "Description: $description"
    if [ -n "$example" ]; then
        echo "Example: $example"
    fi
    echo ""
    
    local value=""
    
    if [ "$is_multiline" = "true" ] || [ "$allow_file_input" = "true" ]; then
        if [ "$allow_file_input" = "true" ]; then
            echo "Options:"
            echo "1. Enter file path to read content"
            echo "2. Paste content manually (press Ctrl+D when done)"
            echo ""
            read -p "Choose option (1 or 2): " input_method
            
            if [ "$input_method" = "1" ]; then
                read -p "Enter file path: " file_path
                if [ -f "$file_path" ]; then
                    value=$(cat "$file_path")
                    print_status "success" "File content loaded from: $file_path"
                else
                    print_status "error" "File not found: $file_path"
                    return 1
                fi
            else
                echo "Paste the content below (press Ctrl+D when done):"
                value=$(cat)
            fi
        else
            echo "Enter the value (press Ctrl+D when done):"
            value=$(cat)
        fi
    else
        read -s -p "Enter the value (hidden): " value
        echo ""
    fi
    
    if [ -z "$value" ]; then
        print_status "warning" "Skipping $secret_name (empty value)"
        return 1
    fi
    
    # Set the secret
    echo "$value" | gh secret set "$secret_name" --repo "$REPO_OWNER/$REPO_NAME"
    print_status "success" "$secret_name has been set"
    return 0
}

# Function to setup secrets interactively
setup_secrets_interactive() {
    echo "🔧 Interactive Secrets Setup"
    echo "============================="
    echo ""
    echo "This will guide you through setting up all required secrets."
    echo "You can skip any secret by pressing Enter with an empty value."
    echo ""
    
    read -p "Continue? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "Setup cancelled."
        exit 0
    fi
    
    # Universal secrets
    echo ""
    echo "📋 Universal Secrets"
    echo "==================="
    prompt_secret "UNITY_LICENSE" "Unity license file content (.ulf file)" "true" "" "true"
    
    # iOS secrets
    echo ""
    echo "🍎 iOS Secrets"
    echo "=============="
    prompt_secret "APPLE_DEVELOPER_EMAIL" "Apple Developer email address" "false" "developer@boardible.com"
    prompt_secret "APPLE_TEAM_ID" "Apple Team ID (10 characters)" "false" "35W3RB2M4Z"
    prompt_secret "APPLE_TEAM_NAME" "Apple Team Name" "false" "Boardible LTDA"
    prompt_secret "APPSTORE_KEY_ID" "App Store Connect API Key ID" "false" "ABC123DEF4"
    prompt_secret "APPSTORE_ISSUER_ID" "App Store Connect API Issuer ID (UUID)" "false" "12345678-1234-1234-1234-123456789abc"
    prompt_secret "APPSTORE_P8_CONTENT" "App Store Connect API Private Key (.p8 file content)" "true" "" "true"
    prompt_secret "MATCH_PASSWORD" "Fastlane Match password" "false" ""
    prompt_secret "REPO_TOKEN" "GitHub token with repo access" "false" "ghp_xxxxxxxxxxxxxxxxxxxx"
    
    # Android secrets
    echo ""
    echo "🤖 Android Secrets"
    echo "=================="
    prompt_secret "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON" "Google Play Service Account JSON content (can load from file)" "true" "" "true"
    
    echo ""
    print_status "info" "For Android keystore, you'll need to base64 encode your .jks/.keystore file"
    echo "Run: base64 -i your_keystore.jks | pbcopy"
    echo "Then paste the result below:"
    prompt_secret "ANDROID_KEYSTORE_BASE64" "Android keystore file (base64 encoded)" "true" "" "true"
    
    prompt_secret "ANDROID_KEYSTORE_PASS" "Android keystore password" "false" ""
    prompt_secret "ANDROID_KEY_ALIAS" "Android key alias name" "false" "uploadkey"
    prompt_secret "ANDROID_KEY_PASS" "Android key password" "false" ""
    
    echo ""
    print_status "success" "Secrets setup completed!"
    echo ""
    print_status "info" "Run './Scripts/checkSecrets.sh' to verify all secrets are configured correctly"
}

# Function to setup from environment file
setup_from_env_file() {
    local env_file=$1
    
    if [ ! -f "$env_file" ]; then
        print_status "error" "Environment file not found: $env_file"
        exit 1
    fi
    
    print_status "info" "Setting up secrets from: $env_file"
    echo ""
    
    # Read and process environment file
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ $line =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # Extract key=value
        if [[ $line =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            # Remove quotes if present
            value="${value%\"}"
            value="${value#\"}"
            value="${value%\'}"
            value="${value#\'}"
            
            # Set the secret
            echo "$value" | gh secret set "$key" --repo "$REPO_OWNER/$REPO_NAME"
            print_status "success" "Set secret: $key"
        fi
    done < "$env_file"
    
    echo ""
    print_status "success" "All secrets from $env_file have been configured!"
}

# Function to remove legacy secrets
remove_legacy_secrets() {
    echo "🗑️  Removing Legacy Secrets"
    echo "=========================="
    echo ""
    
    local legacy_secrets=(
        "ANDROID_KEYSTORE"
        "ANDROID_KEYALIAS_PASS"
        "APPSTORE_P8"
        "MATCH_DEPLOY_KEY"
    )
    
    for secret in "${legacy_secrets[@]}"; do
        if gh secret list --repo "$REPO_OWNER/$REPO_NAME" | grep -q "^$secret"; then
            gh secret remove "$secret" --repo "$REPO_OWNER/$REPO_NAME"
            print_status "success" "Removed legacy secret: $secret"
        else
            print_status "info" "Legacy secret not found: $secret"
        fi
    done
    
    echo ""
    print_status "success" "Legacy secrets cleanup completed!"
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
    
    print_status "info" "Repository: $REPO_OWNER/$REPO_NAME"
}

# Main function
main() {
    echo "=================================================="
    echo "🔐 GitHub Secrets Setup Helper"
    echo "=================================================="
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
    echo ""
    
    case "${1:-interactive}" in
        "--interactive"|"-i"|"interactive")
            setup_secrets_interactive
            ;;
        "--from-env"|"-f")
            if [ -z "$2" ]; then
                print_status "error" "Please specify environment file path"
                echo "Usage: $0 --from-env .env"
                exit 1
            fi
            setup_from_env_file "$2"
            ;;
        "--remove-legacy"|"-r")
            remove_legacy_secrets
            ;;
        "--help"|"-h")
            echo "GitHub Secrets Setup Helper"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --interactive, -i    Interactive secrets setup (default)"
            echo "  --from-env FILE, -f  Set secrets from environment file"
            echo "  --remove-legacy, -r  Remove legacy secrets"
            echo "  --help, -h           Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                       # Interactive setup"
            echo "  $0 --from-env .env      # Setup from .env file"
            echo "  $0 --remove-legacy      # Remove old secrets"
            exit 0
            ;;
        *)
            print_status "error" "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
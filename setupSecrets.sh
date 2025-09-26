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

# Function to setup secrets from local environment files
setup_from_local_env() {
    local script_dir="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    local ios_env="$script_dir/.env.ios.local"
    local android_env="$script_dir/.env.android.local"
    local found_files=()
    
    print_status "info" "Looking for local environment files..."
    
    # Check for iOS environment file
    if [ -f "$ios_env" ]; then
        found_files+=("$ios_env")
        print_status "success" "Found iOS environment file: $ios_env"
    else
        print_status "warning" "iOS environment file not found: $ios_env"
    fi
    
    # Check for Android environment file
    if [ -f "$android_env" ]; then
        found_files+=("$android_env")
        print_status "success" "Found Android environment file: $android_env"
    else
        print_status "warning" "Android environment file not found: $android_env"
    fi
    
    if [ ${#found_files[@]} -eq 0 ]; then
        print_status "error" "No local environment files found!"
        echo ""
        print_status "info" "To create environment files, run:"
        echo "  ./Scripts/setupLocalIOS.sh --create-env     # For iOS"
        echo "  ./Scripts/setupLocalAndroid.sh --create-env # For Android"
        echo ""
        print_status "info" "Then edit the files with your actual secrets and run this script again."
        exit 1
    fi
    
    echo ""
    print_status "info" "Processing ${#found_files[@]} environment file(s)..."
    echo ""
    
    # Process each found environment file
    for env_file in "${found_files[@]}"; do
        local platform=""
        if [[ "$env_file" == *"ios"* ]]; then
            platform="🍎 iOS"
        elif [[ "$env_file" == *"android"* ]]; then
            platform="🤖 Android"
        else
            platform="📋 General"
        fi
        
        echo "==============================================="
        echo "$platform Secrets from $(basename "$env_file")"
        echo "==============================================="
        
        # Read and process environment file
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Skip comments and empty lines
            [[ $line =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
            
            # Extract key=value, handling export statements
            if [[ $line =~ ^export[[:space:]]+([^=]+)=(.*)$ ]] || [[ $line =~ ^([^=]+)=(.*)$ ]]; then
                local key="${BASH_REMATCH[1]}"
                local value="${BASH_REMATCH[2]}"
                
                # Clean up the key (remove 'export' if present)
                key="${key#export }"
                key="${key// /}"
                
                # Remove quotes if present
                value="${value%\"}"
                value="${value#\"}"
                value="${value%\'}"
                value="${value#\'}"
                
                # Skip empty values or placeholder values
                if [ -z "$value" ] || [[ "$value" == *"your-"* ]] || [[ "$value" == *"YOUR_"* ]] || [[ "$value" == *"/path/to"* ]]; then
                    print_status "warning" "Skipping $key (empty or placeholder value)"
                    continue
                fi
                
                # Special handling for Android keystore path - convert to base64
                if [ "$key" = "ANDROID_KEYSTORE_PATH" ]; then
                    if [ -f "$value" ]; then
                        local keystore_base64
                        keystore_base64=$(base64 -i "$value" 2>/dev/null)
                        if [ $? -eq 0 ] && [ -n "$keystore_base64" ]; then
                            # Upload as ANDROID_KEYSTORE_BASE64
                            if echo "$keystore_base64" | gh secret set "ANDROID_KEYSTORE_BASE64" --repo "$REPO_OWNER/$REPO_NAME" 2>/dev/null; then
                                print_status "success" "Converted and set secret: ANDROID_KEYSTORE_PATH -> ANDROID_KEYSTORE_BASE64"
                            else
                                print_status "error" "Failed to set secret: ANDROID_KEYSTORE_BASE64"
                            fi
                        else
                            print_status "error" "Failed to base64 encode keystore: $value"
                        fi
                    else
                        print_status "error" "Keystore file not found: $value"
                    fi
                    continue
                fi
                
                # Special handling for multiline secrets (JSON and P8 keys)
                if [ "$key" = "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON" ] || [ "$key" = "APPSTORE_P8_CONTENT" ]; then
                    # For multiline secrets, we need to handle them differently due to embedded newlines
                    # Skip the normal processing and handle this in a separate pass
                    print_status "info" "Deferring multiline secret: $key (will process after other secrets)"
                    continue
                fi
                
                # Set the secret
                if echo "$value" | gh secret set "$key" --repo "$REPO_OWNER/$REPO_NAME" 2>/dev/null; then
                    print_status "success" "Set secret: $key"
                else
                    print_status "error" "Failed to set secret: $key"
                fi
            fi
        done < "$env_file"
        
        echo ""
    done
    
    # Handle multiline secrets separately
    echo "==============================================="
    echo "🔄 Processing Multiline Secrets"
    echo "==============================================="
    
    for env_file in "${found_files[@]}"; do
        # Handle Google Play Service Account JSON (Android)
        if [[ "$env_file" == *"android"* ]] && grep -q "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON" "$env_file"; then
            if (source "$env_file" 2>/dev/null && [ -n "$GOOGLE_PLAY_SERVICE_ACCOUNT_JSON" ]); then
                # Create a temporary file with the JSON content
                local temp_json=$(mktemp)
                (source "$env_file" && echo "$GOOGLE_PLAY_SERVICE_ACCOUNT_JSON") > "$temp_json"
                
                # Try to set the secret from the file
                if gh secret set "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON" --repo "$REPO_OWNER/$REPO_NAME" < "$temp_json" 2>/dev/null; then
                    print_status "success" "Set secret: GOOGLE_PLAY_SERVICE_ACCOUNT_JSON (JSON content)"
                else
                    print_status "error" "Failed to set secret: GOOGLE_PLAY_SERVICE_ACCOUNT_JSON"
                fi
                
                rm -f "$temp_json"
            else
                print_status "warning" "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON not found or empty in $env_file"
            fi
        fi
        
        # Handle App Store Connect P8 Key (iOS)
        if [[ "$env_file" == *"ios"* ]] && grep -q "APPSTORE_P8_CONTENT" "$env_file"; then
            if (source "$env_file" 2>/dev/null && [ -n "$APPSTORE_P8_CONTENT" ]); then
                # Create a temporary file with the P8 key content
                local temp_p8=$(mktemp)
                (source "$env_file" && echo "$APPSTORE_P8_CONTENT") > "$temp_p8"
                
                # Try to set the secret from the file
                if gh secret set "APPSTORE_P8_CONTENT" --repo "$REPO_OWNER/$REPO_NAME" < "$temp_p8" 2>/dev/null; then
                    print_status "success" "Set secret: APPSTORE_P8_CONTENT (P8 key content)"
                else
                    print_status "error" "Failed to set secret: APPSTORE_P8_CONTENT"
                fi
                
                rm -f "$temp_p8"
            else
                print_status "warning" "APPSTORE_P8_CONTENT not found or empty in $env_file"
            fi
        fi
    done
    echo ""
    
    print_status "success" "All secrets from local environment files have been configured!"
    echo ""
    print_status "info" "Run './Scripts/checkSecrets.sh' to verify all secrets are configured correctly"
}

# Function to get repository info
get_repo_info() {
    local repo_url=""
    local script_dir="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    local project_path="$(dirname "$script_dir")"
    
    # Try to get repository info from parent project (if this is a submodule)
    if [ -d "$project_path/.git" ]; then
        cd "$project_path"
        repo_url=$(git remote get-url origin 2>/dev/null || echo "")
        print_status "info" "Detected parent project repository"
    fi
    
    # Fallback to current directory if parent doesn't have git
    if [ -z "$repo_url" ]; then
        repo_url=$(git remote get-url origin 2>/dev/null || echo "")
        print_status "info" "Using current directory repository"
    fi
    
    if [ -z "$repo_url" ]; then
        print_status "error" "Not in a Git repository or no origin remote found"
        print_status "error" "Make sure to run this script from within a Git project or submodule"
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
    
    case "${1:-local}" in
        "--local"|"-l"|"local")
            setup_from_local_env
            ;;
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
            echo "  --local, -l          Setup from local .env files (default)"
            echo "  --interactive, -i    Interactive secrets setup"
            echo "  --from-env FILE, -f  Set secrets from specific environment file"
            echo "  --remove-legacy, -r  Remove legacy secrets"
            echo "  --help, -h           Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                       # Setup from local .env files (default)"
            echo "  $0 --local              # Setup from local .env files"
            echo "  $0 --interactive        # Interactive setup"
            echo "  $0 --from-env .env      # Setup from specific .env file"
            echo "  $0 --remove-legacy      # Remove old secrets"
            echo ""
            echo "Local Environment Files:"
            echo "  Scripts/.env.ios.local     - iOS secrets"
            echo "  Scripts/.env.android.local - Android secrets"
            echo ""
            echo "Android Keystore Handling:"
            echo "  - Local file uses ANDROID_KEYSTORE_PATH (file path)"
            echo "  - Automatically converts to ANDROID_KEYSTORE_BASE64 for CI/CD"
            echo "  - No manual base64 encoding required"
            echo ""
            echo "To create these files, run:"
            echo "  ./Scripts/setupLocalIOS.sh --create-env"
            echo "  ./Scripts/setupLocalAndroid.sh --create-env"
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
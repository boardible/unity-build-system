#!/bin/bash

# Local iOS Development Setup Helper
# This script helps you set up environment variables for running iosDeploy.sh locally

set -e

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
ENV_FILE="$SCRIPT_DIR/.env.ios.local"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Function to create local environment file
create_local_env() {
    local template_file="$SCRIPT_DIR/.env.ios.local.template"
    
    if [ -f "$template_file" ]; then
        cp "$template_file" "$ENV_FILE"
        print_status "success" "Created local environment file from template: $ENV_FILE"
    else
        # Fallback to inline creation if template doesn't exist
        cat > "$ENV_FILE" << 'EOF'
# Local iOS Development Environment Variables
# Copy this file and fill in your actual values
# DO NOT commit this file to git - it contains sensitive information

# Apple Developer Configuration
export APPLE_DEVELOPER_EMAIL="your-developer@email.com"
export APPLE_TEAM_ID="YOUR_TEAM_ID"  # 10 character team ID
export APPLE_TEAM_NAME="Your Team Name"

# App Store Connect API
export APPSTORE_KEY_ID="YOUR_KEY_ID"
export APPSTORE_ISSUER_ID="YOUR_ISSUER_ID"  # UUID format
export APPSTORE_P8_CONTENT="-----BEGIN PRIVATE KEY-----
YOUR_P8_CONTENT_HERE
-----END PRIVATE KEY-----"

# Fastlane Match
export MATCH_PASSWORD="your_match_password"

# GitHub Token for accessing private repos
export REPO_TOKEN="ghp_your_github_token"

# Optional: Override default values
# export APPLE_CONNECT_EMAIL="support@boardible.com"
# export MATCH_REPOSITORY="boardible/matchCertificate"
# export IOS_APP_ID="com.boardible.ineuj"
# export PROJECT_NAME="INEUJ"
EOF
        print_status "success" "Created local environment file: $ENV_FILE"
    fi

    print_status "success" "Created local environment template: $ENV_FILE"
}

# Function to validate local setup
validate_local_setup() {
    local issues=()
    
    # Check if environment file exists
    if [ ! -f "$ENV_FILE" ]; then
        issues+=("Environment file missing: $ENV_FILE")
    fi
    
    # Check Ruby/Bundler
    if ! command -v bundle &> /dev/null; then
        issues+=("Bundler not installed. Run: gem install bundler")
    fi
    
    # Check if Gemfile exists
    if [ ! -f "$SCRIPT_DIR/../Gemfile" ]; then
        issues+=("Gemfile not found in project root")
    fi
    
    # Check Xcode
    if ! command -v xcodebuild &> /dev/null; then
        issues+=("Xcode command line tools not installed")
    fi
    
    if [ ${#issues[@]} -ne 0 ]; then
        print_status "error" "Local setup issues found:"
        printf '   - %s\n' "${issues[@]}"
        return 1
    else
        print_status "success" "Local setup validation passed"
        return 0
    fi
}

# Function to setup local dependencies
setup_local_deps() {
    print_status "info" "Setting up local dependencies..."
    
    # Navigate to project root
    cd "$SCRIPT_DIR/.."
    
    # Install Ruby dependencies
    if [ -f "Gemfile" ]; then
        print_status "info" "Installing Ruby dependencies..."
        bundle install
        print_status "success" "Ruby dependencies installed"
    fi
    
    print_status "success" "Local dependencies setup completed"
}

# Function to run iOS deploy with local environment
run_ios_deploy() {
    if [ ! -f "$ENV_FILE" ]; then
        print_status "error" "Environment file not found: $ENV_FILE"
        echo "Run: $0 --create-env first"
        exit 1
    fi
    
    print_status "info" "Loading local environment variables..."
    source "$ENV_FILE"
    
    print_status "info" "Running iOS deployment..."
    "$SCRIPT_DIR/iosDeploy.sh"
}

# Main function
main() {
    echo "=================================================="
    echo "🍎 Local iOS Development Setup"
    echo "=================================================="
    echo ""
    
    case "${1:-help}" in
        "--create-env"|"-c")
            create_local_env
            echo ""
            print_status "info" "Next steps:"
            echo "1. Edit $ENV_FILE with your actual values"
            echo "2. Run: $0 --validate to check setup"
            echo "3. Run: $0 --setup-deps to install dependencies"
            echo "4. Run: $0 --deploy to run iOS deployment"
            ;;
        "--validate"|"-v")
            validate_local_setup
            ;;
        "--setup-deps"|"-s")
            validate_local_setup && setup_local_deps
            ;;
        "--deploy"|"-d")
            validate_local_setup && run_ios_deploy
            ;;
        "--help"|"-h"|"help")
            echo "Local iOS Development Setup Helper"
            echo ""
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  --create-env, -c     Create local environment template"
            echo "  --validate, -v       Validate local setup"
            echo "  --setup-deps, -s     Install local dependencies"
            echo "  --deploy, -d         Run iOS deployment with local env"
            echo "  --help, -h           Show this help"
            echo ""
            echo "Quick start:"
            echo "  $0 --create-env"
            echo "  # Edit the created .env file with your values"
            echo "  $0 --setup-deps"
            echo "  $0 --deploy"
            ;;
        *)
            print_status "error" "Unknown command: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
}

main "$@"
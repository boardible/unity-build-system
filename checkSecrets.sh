#!/bin/bash

# GitHub Secrets Checker Script
# This script helps you verify that all required secrets are configured in your GitHub repository

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

# Function to check if gh CLI is installed
check_gh_cli() {
    if ! command -v gh &> /dev/null; then
        print_status "error" "GitHub CLI (gh) is not installed"
        echo ""
        echo "Please install GitHub CLI:"
        echo "  macOS: brew install gh"
        echo "  Linux: https://cli.github.com/manual/installation"
        echo "  Windows: https://cli.github.com/manual/installation"
        echo ""
        echo "After installation, authenticate with: gh auth login"
        exit 1
    fi
    
    # Check if authenticated
    if ! gh auth status &> /dev/null; then
        print_status "error" "GitHub CLI is not authenticated"
        echo ""
        echo "Please authenticate with GitHub CLI:"
        echo "  gh auth login"
        exit 1
    fi
    
    print_status "success" "GitHub CLI is installed and authenticated"
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

# Function to check if a secret exists
check_secret() {
    local secret_name=$1
    local description=$2
    local required=$3
    
    if gh secret list --repo "$REPO_OWNER/$REPO_NAME" | grep -q "^$secret_name"; then
        print_status "success" "$secret_name - $description"
        return 0
    else
        if [ "$required" = "true" ]; then
            print_status "error" "$secret_name - $description (REQUIRED)"
        else
            print_status "warning" "$secret_name - $description (Optional)"
        fi
        return 1
    fi
}

# Main function
main() {
    echo "=================================================="
    echo "🔍 GitHub Repository Secrets Checker"
    echo "=================================================="
    echo ""
    
    # Check prerequisites
    check_gh_cli
    get_repo_info
    echo ""
    
    print_status "info" "Checking repository secrets..."
    echo ""
    
    local missing_required=0
    local missing_optional=0
    
    # Universal secrets
    echo "📋 Universal Secrets:"
    check_secret "UNITY_LICENSE" "Unity license file content" "true" || ((missing_required++))
    echo ""
    
    # iOS secrets
    echo "🍎 iOS Secrets:"
    check_secret "APPLE_DEVELOPER_EMAIL" "Apple Developer email" "true" || ((missing_required++))
    check_secret "APPLE_TEAM_ID" "Apple Team ID" "true" || ((missing_required++))
    check_secret "APPLE_TEAM_NAME" "Apple Team Name" "true" || ((missing_required++))
    check_secret "APPSTORE_KEY_ID" "App Store Connect API Key ID" "true" || ((missing_required++))
    check_secret "APPSTORE_ISSUER_ID" "App Store Connect API Issuer ID" "true" || ((missing_required++))
    check_secret "APPSTORE_P8_CONTENT" "App Store Connect API Private Key" "true" || ((missing_required++))
    check_secret "MATCH_PASSWORD" "Fastlane Match password" "true" || ((missing_required++))
    check_secret "REPO_TOKEN" "GitHub token for Match repository access" "true" || ((missing_required++))
    echo ""
    
    # Android secrets
    echo "🤖 Android Secrets:"
    check_secret "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON" "Google Play Service Account JSON" "true" || ((missing_required++))
    check_secret "ANDROID_KEYSTORE_BASE64" "Android keystore (base64 encoded)" "true" || ((missing_required++))
    check_secret "ANDROID_KEYSTORE_PASS" "Android keystore password" "true" || ((missing_required++))
    check_secret "ANDROID_KEY_ALIAS" "Android key alias" "true" || ((missing_required++))
    check_secret "ANDROID_KEY_PASS" "Android key password" "true" || ((missing_required++))
    echo ""
    
    # Legacy secrets (should be removed)
    echo "🗑️  Legacy Secrets (should be removed):"
    check_secret "ANDROID_KEYSTORE" "Legacy Android keystore" "false" || ((missing_optional++))
    check_secret "ANDROID_KEYALIAS_PASS" "Legacy Android key alias pass" "false" || ((missing_optional++))
    check_secret "APPSTORE_P8" "Legacy App Store P8 key" "false" || ((missing_optional++))
    check_secret "MATCH_DEPLOY_KEY" "Legacy Match deploy key" "false" || ((missing_optional++))
    echo ""
    
    # Summary
    echo "=================================================="
    echo "📊 Summary:"
    echo "=================================================="
    
    if [ $missing_required -eq 0 ]; then
        print_status "success" "All required secrets are configured!"
    else
        print_status "error" "$missing_required required secrets are missing"
    fi
    
    if [ $missing_optional -gt 0 ]; then
        print_status "warning" "$missing_optional legacy secrets found (consider removing)"
    fi
    
    echo ""
    echo "📝 How to add missing secrets:"
    echo "1. Go to: https://github.com/$REPO_OWNER/$REPO_NAME/settings/secrets/actions"
    echo "2. Click 'New repository secret'"
    echo "3. Add each missing secret with its value"
    echo ""
    echo "📖 For detailed instructions, see:"
    echo "   Scripts/CI-CD-ENVIRONMENT-VARIABLES.md"
    echo ""
    
    if [ $missing_required -gt 0 ]; then
        print_status "error" "Cannot run CI/CD builds until all required secrets are configured"
        exit 1
    else
        print_status "success" "Repository is ready for CI/CD builds!"
        exit 0
    fi
}

# Handle command line arguments
case "${1:-}" in
    "--help"|"-h")
        echo "GitHub Repository Secrets Checker"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --list, -l     List all secrets without checking (for debugging)"
        echo ""
        echo "This script checks if all required GitHub repository secrets are configured"
        echo "for the Unity CI/CD pipeline. Run from within your Git repository."
        exit 0
        ;;
    "--list"|"-l")
        check_gh_cli
        get_repo_info
        echo "All secrets in repository $REPO_OWNER/$REPO_NAME:"
        gh secret list --repo "$REPO_OWNER/$REPO_NAME"
        exit 0
        ;;
esac

# Run main function
main
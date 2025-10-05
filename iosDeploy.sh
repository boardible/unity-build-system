#!/bin/bash

# iOS Deployment Script with Modern CI/CD Secret Management
# Uses environment variables instead of encrypted files for better security and CI/CD integration

set -e  # Exit on any error

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_PATH="$(dirname "$SCRIPT_DIR")"

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Load project configuration if it exists
if [ -f "$PROJECT_PATH/project-config.sh" ]; then
    source "$PROJECT_PATH/project-config.sh"
    log "Loaded project configuration from project-config.sh"
fi

# Load local environment variables if they exist
ENV_FILE="$SCRIPT_DIR/.env.ios.local"
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
    log "Loaded local environment variables from $ENV_FILE"
fi

# Set defaults if not configured
export PROJECT_NAME="${PROJECT_NAME:-UnityProject}"
export IOS_APP_ID="${IOS_APP_ID:-com.yourcompany.yourapp}"
export APPLE_CONNECT_EMAIL="${APPLE_CONNECT_EMAIL:-your-email@yourcompany.com}"
export MATCH_REPOSITORY="${MATCH_REPOSITORY:-yourorg/matchCertificate}"
export BUILD_OUTPUT_PATH="${BUILD_OUTPUT_PATH:-build}"

IOS_BUILD_PATH="$PROJECT_PATH/$BUILD_OUTPUT_PATH/iOS"

# Function to validate required environment variables
validate_env_vars() {
    local missing_vars=()
    
    for var in "$@"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        echo "Error: Missing required environment variables:"
        printf ' - %s\n' "${missing_vars[@]}"
        echo ""
        echo "Please set these variables in your CI/CD environment."
        echo "For local development:"
        echo "  1. Run: ./Scripts/setupLocalIOS.sh --create-env"
        echo "  2. Edit: Scripts/.env.ios.local with your values"
        echo "  3. Re-run this script"
        exit 1
    fi
}

log "=== iOS Deployment Script Started ==="

# Validate all required environment variables
validate_env_vars \
    "APPLE_DEVELOPER_EMAIL" \
    "APPLE_TEAM_ID" \
    "APPLE_TEAM_NAME" \
    "APPSTORE_KEY_ID" \
    "APPSTORE_ISSUER_ID" \
    "APPSTORE_P8_CONTENT" \
    "MATCH_PASSWORD" \
    "REPO_TOKEN"

# Ensure CocoaPods specs repo isn\'t duplicated (older git mirror vs CDN trunk)
cleanup_cocoapods_repos() {
    local repos_root="$HOME/.cocoapods/repos"

    if [ ! -d "$repos_root" ]; then
        return
    fi

    # Remove legacy git-based specs repos that conflict with the CDN trunk
    for legacy_repo in "cocoapods" "master"; do
        local legacy_path="$repos_root/$legacy_repo"

        if [ -d "$legacy_path" ]; then
            log "Removing stale CocoaPods specs repo: $legacy_path"
            rm -rf "$legacy_path"
        fi
    done
}

# Run cleanup early to avoid duplicate spec listings later
cleanup_cocoapods_repos

# Export configured values
export IOS_BUILD_PATH="$IOS_BUILD_PATH"

# Set derived data path for Xcode incremental builds
export DERIVED_DATA_PATH="$HOME/Library/Developer/Xcode/DerivedData/Unity-iPhone"

# Check if --clean flag is passed
CLEAN_BUILD=false
for arg in "$@"; do
    if [ "$arg" == "--clean" ]; then
        CLEAN_BUILD=true
        break
    fi
done

# Clean DerivedData if requested (useful after Xcode/Unity updates or linker flag changes)
if [ "$CLEAN_BUILD" == "true" ]; then
    log "Clean build requested - removing DerivedData cache..."
    if [ -d "$DERIVED_DATA_PATH" ]; then
        rm -rf "$DERIVED_DATA_PATH"
        log "DerivedData cleaned: $DERIVED_DATA_PATH"
    fi
    export FASTLANE_CLEAN_BUILD="true"
else
    export FASTLANE_CLEAN_BUILD="false"
fi

# Convert single-line P8 content (with \n) to proper multiline format
export APPSTORE_P8=$(echo -e "$APPSTORE_P8_CONTENT")

log "Environment variables configured successfully"
log "Apple Team ID: $APPLE_TEAM_ID"
log "iOS App ID: $IOS_APP_ID"
log "Build Path: $IOS_BUILD_PATH"
log "Derived Data Path: $DERIVED_DATA_PATH"

# Navigate to project root for Fastlane
cd "$PROJECT_PATH"

# Verify build path exists
if [ ! -d "$IOS_BUILD_PATH" ]; then
    log "Error: iOS build directory not found: $IOS_BUILD_PATH"
    log "Make sure to run the Unity build script first"
    exit 1
fi

# Make shell scripts executable
find "$IOS_BUILD_PATH" -type f -name "*.sh" -exec chmod +x {} \;
find "$IOS_BUILD_PATH" -type f -iname "usymtool" -exec chmod +x {} \;

# Initialize SSH agent for git operations
eval "$(ssh-agent -s)"

# Install Ruby dependencies
log "Installing Ruby dependencies..."
bundle install

# Clean up CocoaPods repos again in case bundler created legacy mirrors via plugins
cleanup_cocoapods_repos

# Deploy to TestFlight
log "Deploying to TestFlight..."
bundle exec fastlane ios beta

log "iOS deployment completed successfully"
exit 0
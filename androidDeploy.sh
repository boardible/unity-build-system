#!/bin/bash

# Android Deployment Script with Modern CI/CD Secret Management
# Uses environment variables instead of encrypted files for better security and CI/CD integration

set -e  # Exit on any error

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_PATH="$(dirname "$SCRIPT_DIR")"

# Load project configuration if it exists
if [ -f "$PROJECT_PATH/project-config.sh" ]; then
    source "$PROJECT_PATH/project-config.sh"
fi

# Set defaults if not configured
export PROJECT_NAME="${PROJECT_NAME:-UnityProject}"
export ANDROID_PACKAGE_NAME="${ANDROID_PACKAGE_NAME:-com.yourcompany.yourapp}"
export BUILD_OUTPUT_PATH="${BUILD_OUTPUT_PATH:-build}"
export DEPLOY_TRACK="${DEPLOY_TRACK:-production}"

ANDROID_BUILD_PATH="$PROJECT_PATH/$BUILD_OUTPUT_PATH/Android"

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

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
        echo "For local development, create a .env file or export them manually."
        exit 1
    fi
}

log "=== Android Deployment Script Started ==="

# Validate all required environment variables
validate_env_vars \
    "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON" \
    "ANDROID_PACKAGE_NAME"

# Log configuration
log "Project: $PROJECT_NAME"
log "Package: $ANDROID_PACKAGE_NAME"
log "Deploy Track: $DEPLOY_TRACK"

# Create temporary service account file from environment variable
TEMP_SERVICE_ACCOUNT_FILE="$PROJECT_PATH/temp_service_account.json"
echo "$GOOGLE_PLAY_SERVICE_ACCOUNT_JSON" > "$TEMP_SERVICE_ACCOUNT_FILE"
export GOOGLE_PLAY_KEY_FILE_PATH="$TEMP_SERVICE_ACCOUNT_FILE"

# Set build file paths (these should be set by the build script)
if [ -z "$ANDROID_BUILD_FILE_PATH" ]; then
    export ANDROID_BUILD_FILE_PATH="$ANDROID_BUILD_PATH/app.aab"
fi

if [ -z "$ANDROID_BUILD_MAPPING_PATH" ]; then
    export ANDROID_BUILD_MAPPING_PATH="$ANDROID_BUILD_PATH/mapping.txt"
fi

log "Environment variables configured successfully"
log "Package Name: $ANDROID_PACKAGE_NAME"
log "Build File: $ANDROID_BUILD_FILE_PATH"
log "Mapping File: $ANDROID_BUILD_MAPPING_PATH"

# Verify build files exist
if [ ! -f "$ANDROID_BUILD_FILE_PATH" ]; then
    log "Error: Android build file not found: $ANDROID_BUILD_FILE_PATH"
    log "Make sure to run the Unity build script first"
    exit 1
fi

# Install dependencies and deploy
log "Installing bundle dependencies..."
bundle install

# Deploy to Play Store
log "Deploying to Google Play Store..."
if [ "$DEPLOY_TRACK" = "internal" ]; then
    bundle exec fastlane android internal
elif [ "$DEPLOY_TRACK" = "alpha" ]; then
    bundle exec fastlane android alpha
elif [ "$DEPLOY_TRACK" = "beta" ]; then
    bundle exec fastlane android beta
else
    # Default to production
    bundle exec fastlane android playprod
fi

# Upload Addressables (if script exists)
ADDRESSABLES_SCRIPT="$SCRIPT_DIR/uploadAddressables-android.sh"
if [ -f "$ADDRESSABLES_SCRIPT" ]; then
    log "Uploading Addressables..."
    source "$ADDRESSABLES_SCRIPT"
else
    log "Warning: Addressables upload script not found: $ADDRESSABLES_SCRIPT"
    log "Skipping Addressables upload"
fi

# Cleanup temporary files
if [ -f "$TEMP_SERVICE_ACCOUNT_FILE" ]; then
    rm "$TEMP_SERVICE_ACCOUNT_FILE"
    log "Cleaned up temporary service account file"
fi

log "Android deployment completed successfully"
exit 0
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

# Load local environment variables if they exist
ENV_FILE="$SCRIPT_DIR/.env.android.local"
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Loaded local environment variables from $ENV_FILE"
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
        echo "For local development:"
        echo "  1. Run: ./Scripts/setupLocalAndroid.sh --create-env"
        echo "  2. Edit: Scripts/.env.android.local with your values"
        echo "  3. Re-run this script"
        exit 1
    fi
}

log "=== Android Deployment Script Started ==="

# Validate all required environment variables
validate_env_vars \
    "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON" \
    "ANDROID_PACKAGE_NAME"

# Validate that GOOGLE_PLAY_SERVICE_ACCOUNT_JSON contains valid JSON
if ! echo "$GOOGLE_PLAY_SERVICE_ACCOUNT_JSON" | python3 -m json.tool > /dev/null 2>&1; then
    log "Error: GOOGLE_PLAY_SERVICE_ACCOUNT_JSON is not valid JSON"
    log "Please check the format of your service account credentials"
    exit 1
fi

# Log configuration
log "Project: $PROJECT_NAME"
log "Package: $ANDROID_PACKAGE_NAME"
log "Deploy Track: $DEPLOY_TRACK"

# Create temporary service account file from environment variable using secure temp file
TEMP_SERVICE_ACCOUNT_FILE=$(mktemp "${TMPDIR:-/tmp}/service_account.XXXXXX.json")
trap "rm -f '$TEMP_SERVICE_ACCOUNT_FILE'" EXIT INT TERM

echo "$GOOGLE_PLAY_SERVICE_ACCOUNT_JSON" > "$TEMP_SERVICE_ACCOUNT_FILE"

# Set environment variables for Fastlane
export GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH="$TEMP_SERVICE_ACCOUNT_FILE"

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

# Generate baseline profile for faster cold start (optional, can be skipped)
log "Checking for baseline profile generation..."
if [ "$GENERATE_BASELINE_PROFILE" = "1" ]; then
    log "Generating baseline profile for cold start optimization..."
    if [ -f "$SCRIPT_DIR/generate-baseline-profile.sh" ]; then
        if "$SCRIPT_DIR/generate-baseline-profile.sh"; then
            log "✅ Baseline profile generated successfully"
            log "Next build will include optimized cold start profile"
        else
            log "⚠️  Baseline profile generation failed, continuing without it"
            log "You can generate it manually later with: ./Scripts/generate-baseline-profile.sh"
        fi
    else
        log "⚠️  Baseline profile script not found, skipping"
    fi
else
    log "Skipping baseline profile generation (set GENERATE_BASELINE_PROFILE=1 to enable)"
    log "Baseline profiles improve cold start by ~15-30%"
fi

# Navigate to project root for Fastlane
cd "$PROJECT_PATH"

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

# Note: Temporary service account file cleanup is handled by trap on EXIT

log "Android deployment completed successfully"
exit 0
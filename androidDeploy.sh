#!/bin/bash#!/bin/bash



# Android Deployment Script with Modern CI/CD Secret Management# Android Deployment Script with Modern CI/CD Secret Management

# Uses environment variables instead of encrypted files for better security and CI/CD integration# Uses environment variables instead of encrypted files for better security and CI/CD integration



set -e  # Exit on any errorset -e  # Exit on any error



SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

PROJECT_PATH="$(dirname "$SCRIPT_DIR")"PROJECT_PATH="$(dirname "$SCRIPT_DIR")"



# Load project configuration if it exists# Load project configuration if it exists

if [ -f "$PROJECT_PATH/project-config.sh" ]; thenif [ -f "$PROJECT_PATH/project-config.sh" ]; then

    source "$PROJECT_PATH/project-config.sh"    source "$PROJECT_PATH/project-config.sh"

fifi



# Set defaults if not configured# Set defaults if not configured

export PROJECT_NAME="${PROJECT_NAME:-UnityProject}"export PROJECT_NAME="${PROJECT_NAME:-UnityProject}"

export ANDROID_PACKAGE_NAME="${ANDROID_PACKAGE_NAME:-com.yourcompany.yourapp}"export ANDROID_PACKAGE_NAME="${ANDROID_PACKAGE_NAME:-com.yourcompany.yourapp}"

export BUILD_OUTPUT_PATH="${BUILD_OUTPUT_PATH:-build}"export BUILD_OUTPUT_PATH="${BUILD_OUTPUT_PATH:-build}"

export DEPLOY_TRACK="${DEPLOY_TRACK:-production}"export DEPLOY_TRACK="${DEPLOY_TRACK:-production}"



ANDROID_BUILD_PATH="$PROJECT_PATH/$BUILD_OUTPUT_PATH/Android"ANDROID_BUILD_PATH="$PROJECT_PATH/$BUILD_OUTPUT_PATH/Android"



# Function to log with timestamp# Function to log with timestamp

log() {log() {

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"

}}



# Function to validate required environment variables# Function to validate required environment variables

validate_env_vars() {validate_env_vars() {

    local missing_vars=()    local missing_vars=()

        

    for var in "$@"; do    for var in "$@"; do

        if [ -z "${!var}" ]; then        if [ -z "${!var}" ]; then

            missing_vars+=("$var")            missing_vars+=("$var")

        fi        fi

    done    done

        

    if [ ${#missing_vars[@]} -ne 0 ]; then    if [ ${#missing_vars[@]} -ne 0 ]; then

        echo "Error: Missing required environment variables:"        echo "Error: Missing required environment variables:"

        printf ' - %s\n' "${missing_vars[@]}"        printf ' - %s\n' "${missing_vars[@]}"

        echo ""        echo ""

        echo "Please set these variables in your CI/CD environment."        echo "Please set these variables in your CI/CD environment."

        echo "For local development, create a .env file or export them manually."        echo "For local development, create a .env file or export them manually."

        exit 1        exit 1

    fi    fi

}}



log "=== Android Deployment Script Started ==="log "=== Android Deployment Script Started ==="



# Validate all required environment variables# Validate all required environment variables

validate_env_vars \validate_env_vars \

    "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON" \    "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON" \

    "ANDROID_PACKAGE_NAME"    "ANDROID_PACKAGE_NAME"



# Log configuration# Log configuration

log "Project: $PROJECT_NAME"log "Project: $PROJECT_NAME"

log "Package: $ANDROID_PACKAGE_NAME"log "Package: $ANDROID_PACKAGE_NAME"

log "Deploy Track: $DEPLOY_TRACK"log "Deploy Track: $DEPLOY_TRACK"



# Create temporary service account file from environment variable# Create temporary service account file from environment variable

TEMP_SERVICE_ACCOUNT_FILE="$PROJECT_PATH/temp_service_account.json"TEMP_SERVICE_ACCOUNT_FILE="$PROJECT_PATH/temp_service_account.json"

echo "$GOOGLE_PLAY_SERVICE_ACCOUNT_JSON" > "$TEMP_SERVICE_ACCOUNT_FILE"echo "$GOOGLE_PLAY_SERVICE_ACCOUNT_JSON" > "$TEMP_SERVICE_ACCOUNT_FILE"

export GOOGLE_PLAY_KEY_FILE_PATH="$TEMP_SERVICE_ACCOUNT_FILE"

# Set environment variables for Fastlane

export GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH="$TEMP_SERVICE_ACCOUNT_FILE"# Set build file paths (these should be set by the build script)

export ANDROID_BUILD_FILE_PATH="$ANDROID_BUILD_PATH/app.aab"if [ -z "$ANDROID_BUILD_FILE_PATH" ]; then

export ANDROID_BUILD_MAPPING_PATH="$ANDROID_BUILD_PATH/mapping.txt"    export ANDROID_BUILD_FILE_PATH="$ANDROID_BUILD_PATH/app.aab"

fi

log "Service account file created: $TEMP_SERVICE_ACCOUNT_FILE"

log "Android build path: $ANDROID_BUILD_PATH"if [ -z "$ANDROID_BUILD_MAPPING_PATH" ]; then

log "Expected build file: $ANDROID_BUILD_FILE_PATH"    export ANDROID_BUILD_MAPPING_PATH="$ANDROID_BUILD_PATH/mapping.txt"

fi

# Verify build file exists

if [ ! -f "$ANDROID_BUILD_FILE_PATH" ]; thenlog "Environment variables configured successfully"

    log "Error: Android build file not found at $ANDROID_BUILD_FILE_PATH"log "Package Name: $ANDROID_PACKAGE_NAME"

    log "Available files in build directory:"log "Build File: $ANDROID_BUILD_FILE_PATH"

    ls -la "$ANDROID_BUILD_PATH" || echo "Build directory not found"log "Mapping File: $ANDROID_BUILD_MAPPING_PATH"

    exit 1

fi# Verify build files exist

if [ ! -f "$ANDROID_BUILD_FILE_PATH" ]; then

# Navigate to project root for Fastlane    log "Error: Android build file not found: $ANDROID_BUILD_FILE_PATH"

cd "$PROJECT_PATH"    log "Make sure to run the Unity build script first"

    exit 1

# Install Ruby dependenciesfi

log "Installing Ruby dependencies..."

bundle install# Install dependencies and deploy

log "Installing bundle dependencies..."

# Deploy to Play Storebundle install

log "Deploying to Google Play Store..."

if [ "$DEPLOY_TRACK" = "internal" ]; then# Deploy to Play Store

    bundle exec fastlane android internallog "Deploying to Google Play Store..."

elif [ "$DEPLOY_TRACK" = "alpha" ]; thenif [ "$DEPLOY_TRACK" = "internal" ]; then

    bundle exec fastlane android alpha    bundle exec fastlane android internal

elif [ "$DEPLOY_TRACK" = "beta" ]; thenelif [ "$DEPLOY_TRACK" = "alpha" ]; then

    bundle exec fastlane android beta    bundle exec fastlane android alpha

elseelif [ "$DEPLOY_TRACK" = "beta" ]; then

    # Default to production    bundle exec fastlane android beta

    bundle exec fastlane android playprodelse

fi    # Default to production

    bundle exec fastlane android playprod

# Cleanup temporary filesfi

log "Cleaning up temporary files..."

rm -f "$TEMP_SERVICE_ACCOUNT_FILE"# Upload Addressables (if script exists)

ADDRESSABLES_SCRIPT="$SCRIPT_DIR/uploadAddressables-android.sh"

log "=== Android Deployment Completed Successfully ==="if [ -f "$ADDRESSABLES_SCRIPT" ]; then

exit 0    log "Uploading Addressables..."
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
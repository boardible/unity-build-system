#!/bin/bash#!/bin/bash



# iOS Deployment Script with Modern CI/CD Secret Management# iOS Deployment Script with Modern CI/CD Secret Management

# Uses environment variables instead of encrypted files for better security and CI/CD integration# Uses environment variables instead of encrypted files for better security and CI/CD integration



set -e  # Exit on any errorset -e  # Exit on any error



SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

PROJECT_PATH="$(dirname "$SCRIPT_DIR")"PROJECT_PATH="$(dirname "$SCRIPT_DIR")"



# Load project configuration if it exists# Load project configuration if it exists

if [ -f "$PROJECT_PATH/project-config.sh" ]; thenif [ -f "$PROJECT_PATH/project-config.sh" ]; then

    source "$PROJECT_PATH/project-config.sh"    source "$PROJECT_PATH/project-config.sh"

    log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }    log "Loaded project configuration from project-config.sh"

    log "Loaded project configuration from project-config.sh"fi

fi

# Set defaults if not configured

# Set defaults if not configuredexport PROJECT_NAME="${PROJECT_NAME:-UnityProject}"

export PROJECT_NAME="${PROJECT_NAME:-UnityProject}"export IOS_APP_ID="${IOS_APP_ID:-com.yourcompany.yourapp}"

export IOS_APP_ID="${IOS_APP_ID:-com.yourcompany.yourapp}"export APPLE_CONNECT_EMAIL="${APPLE_CONNECT_EMAIL:-your-email@yourcompany.com}"

export APPLE_CONNECT_EMAIL="${APPLE_CONNECT_EMAIL:-your-email@yourcompany.com}"export MATCH_REPOSITORY="${MATCH_REPOSITORY:-yourorg/matchCertificate}"

export MATCH_REPOSITORY="${MATCH_REPOSITORY:-yourorg/matchCertificate}"export BUILD_OUTPUT_PATH="${BUILD_OUTPUT_PATH:-build}"

export BUILD_OUTPUT_PATH="${BUILD_OUTPUT_PATH:-build}"

IOS_BUILD_PATH="$PROJECT_PATH/$BUILD_OUTPUT_PATH"

IOS_BUILD_PATH="$PROJECT_PATH/$BUILD_OUTPUT_PATH"

# Function to log with timestamp

# Function to log with timestamplog() {

log() {    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"}

}

# Function to validate required environment variables

# Function to validate required environment variablesvalidate_env_vars() {

validate_env_vars() {    local missing_vars=()

    local missing_vars=()    

        for var in "$@"; do

    for var in "$@"; do        if [ -z "${!var}" ]; then

        if [ -z "${!var}" ]; then            missing_vars+=("$var")

            missing_vars+=("$var")        fi

        fi    done

    done    

        if [ ${#missing_vars[@]} -ne 0 ]; then

    if [ ${#missing_vars[@]} -ne 0 ]; then        echo "Error: Missing required environment variables:"

        echo "Error: Missing required environment variables:"        printf ' - %s\n' "${missing_vars[@]}"

        printf ' - %s\n' "${missing_vars[@]}"        echo ""

        echo ""        echo "Please set these variables in your CI/CD environment."

        echo "Please set these variables in your CI/CD environment."        echo "For local development, create a .env file or export them manually."

        echo "For local development, create a .env file or export them manually."        exit 1

        exit 1    fi

    fi}

}

log "=== iOS Deployment Script Started ==="

log "=== iOS Deployment Script Started ==="

# Validate all required environment variables

# Validate all required environment variablesvalidate_env_vars \

validate_env_vars \    "APPLE_DEVELOPER_EMAIL" \

    "APPLE_DEVELOPER_EMAIL" \    "APPLE_TEAM_ID" \

    "APPLE_TEAM_ID" \    "APPLE_TEAM_NAME" \

    "APPLE_TEAM_NAME" \    "APPSTORE_KEY_ID" \

    "APPSTORE_KEY_ID" \    "APPSTORE_ISSUER_ID" \

    "APPSTORE_ISSUER_ID" \    "APPSTORE_P8_CONTENT" \

    "APPSTORE_P8_CONTENT" \    "MATCH_PASSWORD" \

    "MATCH_PASSWORD" \    "REPO_TOKEN"

    "REPO_TOKEN"

# Export configured values

# Export configured valuesexport IOS_BUILD_PATH="$IOS_BUILD_PATH"

export IOS_BUILD_PATH="$IOS_BUILD_PATH"

# For legacy compatibility, also set APPSTORE_P8 from APPSTORE_P8_CONTENT

# For legacy compatibility, also set APPSTORE_P8 from APPSTORE_P8_CONTENTexport APPSTORE_P8="$APPSTORE_P8_CONTENT"

export APPSTORE_P8="$APPSTORE_P8_CONTENT"

log "Environment variables configured successfully"

log "Environment variables configured successfully"log "Apple Team ID: $APPLE_TEAM_ID"

log "Apple Team ID: $APPLE_TEAM_ID"log "iOS App ID: $IOS_APP_ID"

log "iOS App ID: $IOS_APP_ID"log "Build Path: $IOS_BUILD_PATH"

log "Build Path: $IOS_BUILD_PATH"



#################################################

################################################## check number of args

# check number of args



find $IOS_BUILD_PATH -type f -name "**.sh" -exec chmod +x {} \;

find $IOS_BUILD_PATH -type f -name "**.sh" -exec chmod +x {} \;find $IOS_BUILD_PATH -type f -iname "usymtool" -exec chmod +x {} \;

find $IOS_BUILD_PATH -type f -iname "usymtool" -exec chmod +x {} \;eval "$(ssh-agent -s)"

eval "$(ssh-agent -s)"bundle install

bundle install# pod install removed - handled by Unity post-build script

# pod install removed - handled by Unity post-build scriptbundle exec fastlane ios beta

bundle exec fastlane ios beta

echo "Done."

echo "Done."exit 0
exit 0
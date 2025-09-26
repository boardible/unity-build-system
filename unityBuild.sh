#!/bin/bash

# Unity Build Script with proper CI/CD integration
# This script handles actual Unity builds for both iOS and Android platforms

set -e  # Exit on any error

# Get script directory and project paths
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_PATH="$(dirname "$SCRIPT_DIR")"

# Load project configuration if it exists
if [ -f "$PROJECT_PATH/project-config.sh" ]; then
    source "$PROJECT_PATH/project-config.sh"
fi

# Set defaults if not configured
export PROJECT_NAME="${PROJECT_NAME:-UnityProject}"
export UNITY_VERSION="${UNITY_VERSION:-6000.0.58f1}"
export BUILD_OUTPUT_PATH="${BUILD_OUTPUT_PATH:-build}"
export UNITY_PROJECT_PATH="${UNITY_PROJECT_PATH:-.}"

BUILD_PATH="$PROJECT_PATH/$BUILD_OUTPUT_PATH"
LOGS_PATH="$PROJECT_PATH/Logs"

# Unity paths - adjust based on your Unity installation
UNITY_PATH="/Applications/Unity/Hub/Editor/$UNITY_VERSION/Unity.app/Contents/MacOS/Unity"
if [ ! -f "$UNITY_PATH" ]; then
    # Fallback paths for different Unity installations
    UNITY_PATH="/Applications/Unity/Unity.app/Contents/MacOS/Unity"
    if [ ! -f "$UNITY_PATH" ]; then
        echo "Error: Unity not found. Please update UNITY_PATH in this script."
        exit 1
    fi
fi

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
        echo "Please set these variables in your CI/CD environment or export them locally."
        exit 1
    fi
}

# Function to build Unity project
build_unity() {
    local platform=$1
    local build_target=$2
    local output_path=$3
    local additional_args=$4
    
    log "Building Unity project for $platform..."
    
    # Create build directory
    mkdir -p "$output_path"
    mkdir -p "$LOGS_PATH"
    
    # Unity build command
    local unity_cmd="$UNITY_PATH"
    unity_cmd+=" -batchmode"
    unity_cmd+=" -quit"
    unity_cmd+=" -projectPath $PROJECT_PATH"
    unity_cmd+=" -buildTarget $build_target"
    unity_cmd+=" -buildPath $output_path"
    unity_cmd+=" -executeMethod BuildScript.Build$platform"
    unity_cmd+=" -logFile $LOGS_PATH/unity-build-$platform-$(date +%Y%m%d-%H%M%S).log"
    
    if [ -n "$additional_args" ]; then
        unity_cmd+=" $additional_args"
    fi
    
    log "Executing Unity build command..."
    log "Command: $unity_cmd"
    
    # Execute Unity build
    eval "$unity_cmd"
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log "Unity build for $platform completed successfully"
    else
        log "Unity build for $platform failed with exit code $exit_code"
        log "Check log file: $LOGS_PATH/unity-build-$platform-*.log"
        exit $exit_code
    fi
}

# Function to build Addressables
build_addressables() {
    local platform=$1
    
    log "Building Addressables for $platform..."
    
    local unity_cmd="$UNITY_PATH"
    unity_cmd+=" -batchmode"
    unity_cmd+=" -quit"
    unity_cmd+=" -projectPath $PROJECT_PATH"
    unity_cmd+=" -executeMethod BuildScript.BuildAddressables"
    unity_cmd+=" -buildTarget $platform"
    unity_cmd+=" -logFile $LOGS_PATH/addressables-build-$platform-$(date +%Y%m%d-%H%M%S).log"
    
    log "Building Addressables..."
    eval "$unity_cmd"
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log "Addressables build for $platform completed successfully"
    else
        log "Addressables build for $platform failed with exit code $exit_code"
        exit $exit_code
    fi
}

# iOS Build Function
build_ios() {
    log "=== iOS Build Process ==="
    
    # Validate iOS environment variables
    validate_env_vars "IOS_APP_ID" "APPLE_TEAM_ID"
    
    local ios_build_path="$BUILD_PATH/iOS"
    
    # Build Addressables first
    build_addressables "iOS"
    
    # Build Unity iOS project
    build_unity "iOS" "iOS" "$ios_build_path" "-development"
    
    log "iOS Unity build completed. Xcode project available at: $ios_build_path"
    
    # Set environment variables for downstream processes
    export IOS_BUILD_PATH="$ios_build_path"
}

# Android Build Function
build_android() {
    log "=== Android Build Process ==="
    
    # Validate Android environment variables
    validate_env_vars "ANDROID_PACKAGE_NAME" "ANDROID_KEYSTORE_PATH" "ANDROID_KEYSTORE_PASS" "ANDROID_KEY_ALIAS" "ANDROID_KEY_PASS"
    
    local android_build_path="$BUILD_PATH/Android"
    
    # Build Addressables first
    build_addressables "Android"
    
    # Set Android keystore environment variables for Unity
    export ANDROID_KEYSTORE_PATH
    export ANDROID_KEYSTORE_PASS
    export ANDROID_KEY_ALIAS
    export ANDROID_KEY_PASS
    
    # Build Unity Android project (AAB format)
    build_unity "Android" "Android" "$android_build_path/app.aab" "-buildAppBundle"
    
    log "Android Unity build completed. AAB file available at: $android_build_path/app.aab"
    
    # Set environment variables for downstream processes
    export ANDROID_BUILD_FILE_PATH="$android_build_path/app.aab"
    export ANDROID_BUILD_MAPPING_PATH="$android_build_path/mapping.txt"
}

# Main script logic
main() {
    log "=== Unity Build Script Started ==="
    log "Project Path: $PROJECT_PATH"
    log "Unity Path: $UNITY_PATH"
    
    # Parse command line arguments
    PLATFORM=""
    RELEASE_MODE="development"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --platform)
                PLATFORM="$2"
                shift 2
                ;;
            --release)
                RELEASE_MODE="release"
                shift
                ;;
            --help)
                echo "Usage: $0 --platform [ios|android|both] [--release]"
                echo ""
                echo "Options:"
                echo "  --platform    Target platform: ios, android, or both"
                echo "  --release     Build in release mode (default: development)"
                echo "  --help        Show this help message"
                echo ""
                echo "Required Environment Variables:"
                echo "For iOS:"
                echo "  IOS_APP_ID                - iOS app identifier"
                echo "  APPLE_TEAM_ID             - Apple Developer Team ID"
                echo ""
                echo "For Android:"
                echo "  ANDROID_PACKAGE_NAME      - Android package name"
                echo "  ANDROID_KEYSTORE_PATH     - Path to Android keystore"
                echo "  ANDROID_KEYSTORE_PASS     - Android keystore password"
                echo "  ANDROID_KEY_ALIAS         - Android key alias"
                echo "  ANDROID_KEY_PASS          - Android key password"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Validate platform argument
    if [ -z "$PLATFORM" ]; then
        echo "Error: Platform not specified. Use --platform [ios|android|both]"
        exit 1
    fi
    
    # Set build mode environment variable
    export UNITY_BUILD_MODE="$RELEASE_MODE"
    
    # Execute builds based on platform
    case $PLATFORM in
        ios)
            build_ios
            ;;
        android)
            build_android
            ;;
        both)
            build_ios
            build_android
            ;;
        *)
            echo "Error: Invalid platform '$PLATFORM'. Use ios, android, or both."
            exit 1
            ;;
    esac
    
    log "=== Unity Build Script Completed Successfully ==="
}

# Run main function with all arguments
main "$@"
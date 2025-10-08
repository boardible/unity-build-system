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

# Load local environment variables if they exist
if [ -f "$SCRIPT_DIR/.env.ios.local" ]; then
    source "$SCRIPT_DIR/.env.ios.local"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Loaded iOS environment variables"
fi
if [ -f "$SCRIPT_DIR/.env.android.local" ]; then
    source "$SCRIPT_DIR/.env.android.local"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Loaded Android environment variables"
fi

# Auto-detect Unity version from ProjectSettings/ProjectVersion.txt
detect_unity_version() {
    local version_file="$PROJECT_PATH/ProjectSettings/ProjectVersion.txt"
    if [ -f "$version_file" ]; then
        # Extract version from m_EditorVersion line
        local detected_version=$(grep "m_EditorVersion:" "$version_file" | sed 's/m_EditorVersion: //' | tr -d '[:space:]')
        if [ -n "$detected_version" ]; then
            echo "$detected_version"
            return 0
        fi
    fi
    return 1
}

# Set defaults if not configured
export PROJECT_NAME="${PROJECT_NAME:-UnityProject}"
# Try to detect Unity version from project, fallback to environment variable or default
if [ -z "$UNITY_VERSION" ]; then
    DETECTED_VERSION=$(detect_unity_version)
    if [ -n "$DETECTED_VERSION" ]; then
        export UNITY_VERSION="$DETECTED_VERSION"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Auto-detected Unity version: $UNITY_VERSION"
    else
        export UNITY_VERSION="6000.0.58f2"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Using default Unity version: $UNITY_VERSION"
    fi
fi
export BUILD_OUTPUT_PATH="${BUILD_OUTPUT_PATH:-build}"
export UNITY_PROJECT_PATH="${UNITY_PROJECT_PATH:-.}"

BUILD_PATH="$PROJECT_PATH/$BUILD_OUTPUT_PATH"
LOGS_PATH="$PROJECT_PATH/Logs"

# Unity paths - try multiple locations
detect_unity_path() {
    local version="$1"
    local paths=(
        "/Applications/Unity/Hub/Editor/$version/Unity.app/Contents/MacOS/Unity"
        "/Applications/Unity/Unity.app/Contents/MacOS/Unity"
        "$HOME/Applications/Unity/Hub/Editor/$version/Unity.app/Contents/MacOS/Unity"
    )
    
    # First try exact version match
    for path in "${paths[@]}"; do
        if [ -f "$path" ]; then
            echo "$path"
            return 0
        fi
    done
    
    # If exact match fails, try fuzzy match (e.g., 6000.0.58f2 -> 6000.0.58f*)
    local major_version="${version%%.*}"  # Extract major version (e.g., "6000")
    local fuzzy_pattern="/Applications/Unity/Hub/Editor/${major_version}.*/Unity.app/Contents/MacOS/Unity"
    
    # Use compgen to expand glob safely
    local expanded_paths
    shopt -s nullglob
    expanded_paths=($fuzzy_pattern)
    shopt -u nullglob
    
    if [ ${#expanded_paths[@]} -gt 0 ]; then
        # Return the first match
        echo "${expanded_paths[0]}"
        return 0
    fi
    
    return 1
}

UNITY_PATH=$(detect_unity_path "$UNITY_VERSION")
if [ -z "$UNITY_PATH" ]; then
    echo "Error: Unity $UNITY_VERSION not found."
    echo "Checked locations:"
    echo "  - /Applications/Unity/Hub/Editor/$UNITY_VERSION/Unity.app/Contents/MacOS/Unity"
    echo "  - /Applications/Unity/Unity.app/Contents/MacOS/Unity"
    echo "  - ~/Applications/Unity/Hub/Editor/$UNITY_VERSION/Unity.app/Contents/MacOS/Unity"
    echo ""
    echo "Project requires Unity version: $UNITY_VERSION (from ProjectSettings/ProjectVersion.txt)"
    echo "Please install Unity $UNITY_VERSION via Unity Hub or set UNITY_PATH environment variable."
    exit 1
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Found Unity at: $UNITY_PATH"
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
    local profile=$4
    local additional_args=$5
    
    log "Building Unity project for $platform using $profile profile..."
    
    # Create build directory (handle file outputs like .aab/.apk)
    case "$output_path" in
        *.aab|*.apk)
            mkdir -p "$(dirname "$output_path")"
            ;;
        *)
            mkdir -p "$output_path"
            ;;
    esac
    mkdir -p "$LOGS_PATH"
    
    # Unity build command WITHOUT -quit (BuildScript.cs handles exit via EditorApplication.Exit)
    local unity_cmd="$UNITY_PATH"
    # NOTE: -quit removed because BuildScript.cs async methods call EditorApplication.Exit() manually
    unity_cmd+=" -batchmode"
    unity_cmd+=" -nographics"
    unity_cmd+=" -projectPath $PROJECT_PATH"
    unity_cmd+=" -buildTarget $build_target"
    unity_cmd+=" -buildPath $output_path"
    # Handle case sensitivity for method names
    local method_name
    case $platform in
        iOS)
            method_name="BuildiOS"
            ;;
        Android)
            method_name="BuildAndroid"
            ;;
        *)
            method_name="Build$platform"
            ;;
    esac
    unity_cmd+=" -executeMethod BuildScript.$method_name"
    unity_cmd+=" -profile $profile"
    unity_cmd+=" -stackTraceLogType None"
    
    if [ -n "$additional_args" ]; then
        unity_cmd+=" $additional_args"
    fi
    
    log "Executing Unity build command..."
    log "Command: $unity_cmd"
    
    # Execute Unity build with real-time output and log file
    local log_file="$LOGS_PATH/unity-build-$platform-$(date +%Y%m%d-%H%M%S).log"
    
    # Run Unity directly without eval for security
    "$UNITY_PATH" -batchmode -nographics \
        -projectPath "$PROJECT_PATH" \
        -buildTarget "$build_target" \
        -buildPath "$output_path" \
        -executeMethod "BuildScript.$method_name" \
        -profile "$profile" \
        -stackTraceLogType None \
        $additional_args \
        2>&1 | tee "$log_file"
    local exit_code=${PIPESTATUS[0]}
    
    if [ $exit_code -eq 0 ]; then
        log "Unity build for $platform completed successfully"
        log "Log file: $log_file"
    else
        log "Unity build for $platform failed with exit code $exit_code"
        log "Check log file: $log_file"
        log "Last 20 lines of build log:"
        tail -20 "$log_file" 2>/dev/null || echo "Could not read log file"
        exit $exit_code
    fi
}

# Function to build Addressables
build_addressables() {
    local platform=$1
    
    log "Building Addressables for $platform..."
    
    # Unity command WITHOUT -quit (BuildScript.cs handles exit via EditorApplication.Exit)
    local unity_cmd="$UNITY_PATH"
    # NOTE: -quit removed because BuildScript.cs calls EditorApplication.Exit() manually
    unity_cmd+=" -batchmode"
    unity_cmd+=" -nographics"
    unity_cmd+=" -projectPath $PROJECT_PATH"
    unity_cmd+=" -executeMethod BuildScript.BuildAddressables"
    unity_cmd+=" -buildTarget $platform"
    unity_cmd+=" -stackTraceLogType None"
    
    log "Building Addressables..."
    local log_file="$LOGS_PATH/addressables-build-$platform-$(date +%Y%m%d-%H%M%S).log"
    
    # Run Unity directly without eval for security
    "$UNITY_PATH" -batchmode -nographics \
        -projectPath "$PROJECT_PATH" \
        -executeMethod "BuildScript.BuildAddressables" \
        -buildTarget "$platform" \
        -stackTraceLogType None \
        2>&1 | tee "$log_file"
    local exit_code=${PIPESTATUS[0]}
    
    if [ $exit_code -eq 0 ]; then
        log "Addressables build for $platform completed successfully"
        log "Log file: $log_file"
    else
        log "Addressables build for $platform failed with exit code $exit_code"
        log "Check log file: $log_file"
        exit $exit_code
    fi
}

# iOS Build Function
build_ios() {
    log "=== iOS Build Process ==="
    
    # Validate iOS environment variables
    validate_env_vars "IOS_APP_ID" "APPLE_TEAM_ID"
    
    local ios_build_path="$BUILD_PATH/iOS"
    
    # Build Unity iOS project (Addressables + Build in single session)
    # Note: BoardDoctor removed - run Scripts/runBoardDoctor.sh separately if needed
    build_unity "iOS" "iOS" "$ios_build_path" "$PROFILE"
    
    log "iOS Unity build completed. Xcode project available at: $ios_build_path"
    
    # SAFETY NET: Clean up duplicate CocoaPods sources in Podfile
    # This ensures Podfile only has ONE source line (CDN) before pod install
    local podfile_path="$ios_build_path/Podfile"
    if [ -f "$podfile_path" ]; then
        log "Checking Podfile for duplicate sources..."
        
        # Count source lines
        local source_count=$(grep -c "^source " "$podfile_path" 2>/dev/null || echo "0")
        
        if [ "$source_count" -gt 1 ]; then
            log "⚠️  Found $source_count source lines in Podfile, cleaning up duplicates..."
            
            # Show what we found
            log "Current sources:"
            grep "^source " "$podfile_path" | while read -r line; do
                log "  - $line"
            done
            
            # Keep only the first source line (CDN), remove all others
            # Create a temp file with all lines except duplicate source lines
            local temp_file="${podfile_path}.tmp"
            local found_source=false
            
            while IFS= read -r line; do
                if [[ "$line" =~ ^source ]]; then
                    if [ "$found_source" = false ]; then
                        # First source line - ensure it's the CDN source
                        echo "source 'https://cdn.cocoapods.org/'" >> "$temp_file"
                        found_source=true
                        log "✓ Kept CDN source"
                    else
                        # Duplicate source line - skip it
                        log "✗ Removed duplicate: $line"
                    fi
                else
                    echo "$line" >> "$temp_file"
                fi
            done < "$podfile_path"
            
            # Replace original with cleaned version
            mv "$temp_file" "$podfile_path"
            
            log "✓ Podfile cleaned - now has single source"
            log "Final sources:"
            grep "^source " "$podfile_path" | while read -r line; do
                log "  - $line"
            done
        else
            log "✓ Podfile already has single source (count: $source_count)"
        fi
    else
        log "⚠️  Podfile not found at: $podfile_path"
    fi
    
    # Set environment variables for downstream processes
    export IOS_BUILD_PATH="$ios_build_path"
}

# Android Build Function
build_android() {
    log "=== Android Build Process ==="
    
    # Validate Android environment variables
    validate_env_vars "ANDROID_PACKAGE_NAME" "ANDROID_KEYSTORE_PATH" "ANDROID_KEYSTORE_PASS" "ANDROID_KEY_ALIAS" "ANDROID_KEY_PASS"
    
    local android_build_path="$BUILD_PATH/Android"
    
    # Set Android keystore environment variables for Unity
    export ANDROID_KEYSTORE_PATH
    export ANDROID_KEYSTORE_PASS
    export ANDROID_KEY_ALIAS
    export ANDROID_KEY_PASS
    
    # Build Unity Android project (now includes BoardDoctor + Addressables + Build in single session)
    build_unity "Android" "Android" "$android_build_path/app.aab" "$PROFILE" "-buildAppBundle"
    
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
    PROFILE="dev"  # Default to dev profile
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --platform)
                PLATFORM="$2"
                shift 2
                ;;
            --profile)
                PROFILE="$2"
                shift 2
                ;;
            --release)
                RELEASE_MODE="release"
                PROFILE="prod"  # Automatically set prod profile for release builds
                shift
                ;;
            --help)
                echo "Usage: $0 --platform [ios|android|both] [--profile dev|prod] [--release]"
                echo ""
                echo "Options:"
                echo "  --platform           Target platform: ios, android, or both"
                echo "  --profile            Build profile: dev or prod (default: dev, auto-set to prod with --release)"
                echo "  --release            Build in release mode and use prod profile (default: development mode with dev profile)"
                echo "  --help               Show this help message"
                echo ""
                echo "Note: BoardDoctor has been removed from the build process."
                echo "      Run Scripts/runBoardDoctor.sh separately when game data needs refresh."
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

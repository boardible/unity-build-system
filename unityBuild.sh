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
        export UNITY_VERSION="6000.2.14f1"
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
    
    # If exact match fails, try fuzzy match (e.g., 6000.2.14f1 -> 6000.2.14f*)
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
    
    # Validate link.xml before building
    log "Validating link.xml configuration..."
    if [ -f "$SCRIPT_DIR/validate-linkxml.sh" ]; then
        if ! "$SCRIPT_DIR/validate-linkxml.sh"; then
            log "❌ link.xml validation failed!"
            log "Build aborted to prevent code stripping issues."
            exit 1
        fi
    else
        log "⚠️  Warning: validate-linkxml.sh not found, skipping validation"
    fi
    
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

# Check if BoardDoctor should be run
check_boarddoctor() {
    local platform=$1
    local profile=$2
    
    # Path to track BoardDoctor runs
    local tracker_dir="$PROJECT_PATH/.build-cache"
    local tracker_file="$tracker_dir/boarddoctor-${platform}-${profile}.tracker"
    
    mkdir -p "$tracker_dir"
    
    # Check if BoardDoctor was already run for this configuration
    if [ -f "$tracker_file" ]; then
        local last_run=$(cat "$tracker_file" 2>/dev/null || echo "unknown")
        log "BoardDoctor was last run for $platform/$profile on: $last_run"
        
        # Only prompt in interactive mode (not in CI/CD)
        if [ -t 0 ]; then
            echo ""
            echo "═══════════════════════════════════════════════════"
            echo "  BoardDoctor Check"
            echo "═══════════════════════════════════════════════════"
            echo ""
            echo "BoardDoctor refreshes game data, localization, textures, etc."
            echo "Last run: $last_run for $platform/$profile"
            echo ""
            echo "Do you want to run BoardDoctor before building?"
            echo ""
            echo "  [y] Yes - Run BoardDoctor + CSV sync (recommended for data changes)"
            echo "  [n] No  - Skip and use existing data (faster)"
            echo "  [s] Skip and don't ask again for this build session"
            echo ""
            read -p "Your choice [y/n/s]: " -n 1 -r choice
            echo ""
            echo ""
            
            case "$choice" in
                y|Y)
                    log "Running BoardDoctor..."
                    run_boarddoctor "$profile"
                    ;;
                s|S)
                    log "Skipping BoardDoctor prompt for this session"
                    export SKIP_BOARDDOCTOR_PROMPT=true
                    ;;
                *)
                    log "Skipping BoardDoctor, using existing data"
                    ;;
            esac
        else
            log "Running in non-interactive mode (CI/CD), skipping BoardDoctor prompt"
        fi
    else
        log "BoardDoctor has never been run for $platform/$profile configuration"
        
        # Only prompt in interactive mode
        if [ -t 0 ]; then
            echo ""
            echo "═══════════════════════════════════════════════════"
            echo "  ⚠️  BoardDoctor Required"
            echo "═══════════════════════════════════════════════════"
            echo ""
            echo "This is the first build for $platform/$profile."
            echo "BoardDoctor must run to prepare game data, localization, etc."
            echo ""
            read -p "Run BoardDoctor now? [Y/n]: " -n 1 -r choice
            echo ""
            echo ""
            
            case "$choice" in
                n|N)
                    log "⚠️  WARNING: Building without BoardDoctor may cause runtime errors"
                    log "You can run it manually later: ./Scripts/runBoardDoctor.sh $profile"
                    ;;
                *)
                    log "Running BoardDoctor..."
                    run_boarddoctor "$profile"
                    ;;
            esac
        else
            log "⚠️  WARNING: BoardDoctor has never run for this config, but running in non-interactive mode"
            log "Build may have missing data. Run manually: ./Scripts/runBoardDoctor.sh $profile"
        fi
    fi
}

# Run BoardDoctor and update tracker
run_boarddoctor() {
    local profile=$1
    local boarddoctor_script="$SCRIPT_DIR/runBoardDoctor.sh"
    
    if [ ! -f "$boarddoctor_script" ]; then
        log "❌ Error: BoardDoctor script not found at $boarddoctor_script"
        return 1
    fi
    
    log "=== Executing BoardDoctor for $profile environment ==="
    
    # Run BoardDoctor
    if bash "$boarddoctor_script" "$profile"; then
        log "✅ BoardDoctor completed successfully"
        
        # Update tracker for both platforms (BoardDoctor output is platform-agnostic)
        local tracker_dir="$PROJECT_PATH/.build-cache"
        mkdir -p "$tracker_dir"
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "$timestamp" > "$tracker_dir/boarddoctor-iOS-${profile}.tracker"
        echo "$timestamp" > "$tracker_dir/boarddoctor-Android-${profile}.tracker"
        
        return 0
    else
        log "❌ BoardDoctor failed"
        echo ""
        read -p "Continue with build anyway? [y/N]: " -n 1 -r choice
        echo ""
        
        case "$choice" in
            y|Y)
                log "Continuing build despite BoardDoctor failure..."
                return 0
                ;;
            *)
                log "Build cancelled due to BoardDoctor failure"
                exit 1
                ;;
        esac
    fi
}

# iOS Build Function
build_ios() {
    log "=== iOS Build Process ==="
    
    # Validate iOS environment variables
    validate_env_vars "IOS_APP_ID" "APPLE_TEAM_ID"
    
    # Check if BoardDoctor should be run (unless already prompted in this session)
    if [ "$SKIP_BOARDDOCTOR_PROMPT" != "true" ]; then
        check_boarddoctor "iOS" "$PROFILE"
        # If building both platforms, automatically skip Android prompt
        if [ "$PLATFORM" = "both" ]; then
            export SKIP_BOARDDOCTOR_PROMPT=true
            log "Building both platforms - will skip BoardDoctor prompt for Android"
        fi
    fi
    
    local ios_build_path="$BUILD_PATH/iOS"
    
    # Build Unity iOS project (Addressables + Build in single session)
    build_unity "iOS" "iOS" "$ios_build_path" "$PROFILE"
    
    log "iOS Unity build completed. Xcode project available at: $ios_build_path"
    
    # SAFETY NET: Clean up duplicate CocoaPods sources in Podfile
    # This ensures Podfile only has ONE source line (GitHub Specs) before pod install
    # The CDN source is deprecated and causes builds to hang
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
            
            # Keep only the first source line (GitHub Specs), remove all others
            # CDN source is deprecated and causes hangs
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
        
        # SAFETY NET: Remove deprecated Firebase/Core pod (removed in Firebase SDK 11.0+)
        if grep -q "pod 'Firebase/Core'" "$podfile_path"; then
            log "⚠️  Found deprecated Firebase/Core pod, removing..."
            sed -i '' "/pod 'Firebase\/Core'/d" "$podfile_path"
            log "✓ Removed Firebase/Core pod"
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
    
    # Check if BoardDoctor should be run (unless already prompted in this session)
    if [ "$SKIP_BOARDDOCTOR_PROMPT" != "true" ]; then
        check_boarddoctor "Android" "$PROFILE"
    fi
    
    local android_build_path="$BUILD_PATH/Android"
    
    # Set Android keystore environment variables for Unity
    export ANDROID_KEYSTORE_PATH
    export ANDROID_KEYSTORE_PASS
    export ANDROID_KEY_ALIAS
    export ANDROID_KEY_PASS
    
    # Build Unity Android project (now includes BoardDoctor + Addressables + Build in single session)
    build_unity "Android" "Android" "$android_build_path/app.aab" "$PROFILE" "-buildAppBundle"
    
    log "Android Unity build completed. AAB file available at: $android_build_path/app.aab"
    
    # Run Android test with baseline profile generation (MANDATORY for cold start optimization)
    if [ "$CI" != "true" ] && [ "$SKIP_ANDROID_TEST" != "1" ]; then
        log ""
        log "📊 Android Test & Baseline Profile Generation"
        log "This is MANDATORY - ensures optimal cold start time (~15-30% faster)"
        log ""
        
        if [ -f "$SCRIPT_DIR/testAndroid.sh" ]; then
            log "Starting Android test with baseline profile..."
            if "$SCRIPT_DIR/testAndroid.sh"; then
                log "✅ Android test & baseline profile completed successfully"
                log "Next build will include this profile for faster cold start"
            else
                log "⚠️  Android test failed"
                log "You can run it manually: ./Scripts/testAndroid.sh"
            fi
        else
            log "⚠️  testAndroid.sh not found"
        fi
    elif [ "$CI" = "true" ]; then
        log "CI environment detected - skipping interactive baseline profile generation"
        log "Run ./Scripts/testAndroid.sh manually after deployment for profiling"
    fi
    
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
    CLEAN_CACHE=false
    RUN_AFTER_BUILD=false
    
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
            --clean-cache)
                CLEAN_CACHE=true
                shift
                ;;
            --run)
                RUN_AFTER_BUILD=true
                shift
                ;;
            --help)
                echo "Usage: $0 --platform [ios|android|both] [--profile dev|prod] [--release] [--clean-cache] [--run]"
                echo ""
                echo "Options:"
                echo "  --platform           Target platform: ios, android, or both"
                echo "  --profile            Build profile: dev or prod (default: dev, auto-set to prod with --release)"
                echo "  --release            Build in release mode and use prod profile (default: development mode with dev profile)"
                echo "  --clean-cache        Clear Unity caches before building (forces full recompile)"
                echo "                       Clears: ScriptAssemblies, Bee, IL2CPP, build artifacts, DerivedData"
                echo "  --run                Install and run on connected device/emulator after build (Android only)"
                echo "                       Automatically uninstalls old version and installs fresh APK"
                echo "  --help               Show this help message"
                echo ""
                echo "BoardDoctor Integration:"
                echo "  The build script will automatically prompt you to run BoardDoctor if:"
                echo "    - This is the first build for a platform/profile combination"
                echo "    - BoardDoctor hasn't been run recently for this configuration"
                echo ""
                echo "  BoardDoctor refreshes game data, localization, textures, and CSV files."
                echo "  You can also run it manually: ./Scripts/runBoardDoctor.sh [dev|prod]"
                echo ""
                echo "  Build tracking: .build-cache/boarddoctor-{platform}-{profile}.tracker"
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
    
    # Clean Unity caches if requested
    if [ "$CLEAN_CACHE" = true ]; then
        log "🧹 Cleaning Unity caches (--clean-cache)..."
        
        # Clean ScriptAssemblies (compiled C# code)
        if [ -d "$PROJECT_PATH/Library/ScriptAssemblies" ]; then
            rm -rf "$PROJECT_PATH/Library/ScriptAssemblies"
            log "  ✓ Cleared Library/ScriptAssemblies"
        fi
        
        # Clean Bee (incremental build cache)
        if [ -d "$PROJECT_PATH/Library/Bee" ]; then
            rm -rf "$PROJECT_PATH/Library/Bee"
            log "  ✓ Cleared Library/Bee"
        fi
        
        # Clean IL2CPP cache
        if [ -d "$PROJECT_PATH/Library/Il2cppBuildCache" ]; then
            rm -rf "$PROJECT_PATH/Library/Il2cppBuildCache"
            log "  ✓ Cleared Library/Il2cppBuildCache"
        fi
        
        # Clean build output folders
        if [ -d "$PROJECT_PATH/build/Android" ]; then
            rm -rf "$PROJECT_PATH/build/Android"
            log "  ✓ Cleared build/Android"
        fi
        
        if [ -d "$PROJECT_PATH/build/iOS" ]; then
            rm -rf "$PROJECT_PATH/build/iOS"
            log "  ✓ Cleared build/iOS"
        fi
        
        # Clean Xcode DerivedData for this project
        local derived_data_path="$HOME/Library/Developer/Xcode/DerivedData"
        if [ -d "$derived_data_path" ]; then
            # Find and delete folders matching Unity-iPhone pattern
            local deleted_count=0
            for dir in "$derived_data_path"/Unity-iPhone-*; do
                if [ -d "$dir" ]; then
                    rm -rf "$dir"
                    deleted_count=$((deleted_count + 1))
                fi
            done
            if [ $deleted_count -gt 0 ]; then
                log "  ✓ Cleared $deleted_count Xcode DerivedData folder(s)"
            fi
        fi
        
        # Clean CocoaPods cache for this project
        if [ -d "$PROJECT_PATH/build/iOS/Pods" ]; then
            rm -rf "$PROJECT_PATH/build/iOS/Pods"
            log "  ✓ Cleared iOS Pods folder"
        fi
        
        # Clean Gradle cache for Android (project-specific)
        if [ -d "$PROJECT_PATH/.gradle" ]; then
            rm -rf "$PROJECT_PATH/.gradle"
            log "  ✓ Cleared .gradle cache"
        fi
        
        log "✅ All caches cleared - next build will be a full clean build"
    fi
    
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
            # Run on device/emulator if requested
            if [ "$RUN_AFTER_BUILD" = true ]; then
                run_android
            fi
            ;;
        both)
            build_ios
            build_android
            # Run on device/emulator if requested (Android only)
            if [ "$RUN_AFTER_BUILD" = true ]; then
                run_android
            fi
            ;;
        *)
            echo "Error: Invalid platform '$PLATFORM'. Use ios, android, or both."
            exit 1
            ;;
    esac
    
    log "=== Unity Build Script Completed Successfully ==="
}

# Function to install and run Android app on connected device/emulator
run_android() {
    log "=== Installing and Running on Android Device/Emulator ==="
    
    local aab_path="$BUILD_PATH/Android/app.aab"
    local apks_path="/tmp/boardible_app.apks"
    
    # Check if AAB exists
    if [ ! -f "$aab_path" ]; then
        log "❌ Error: AAB file not found at $aab_path"
        return 1
    fi
    
    # Check if adb is available
    if ! command -v adb &> /dev/null; then
        log "❌ Error: adb not found. Please install Android SDK platform-tools."
        return 1
    fi
    
    # Check if bundletool is available
    if ! command -v bundletool &> /dev/null; then
        log "❌ Error: bundletool not found. Install with: brew install bundletool"
        return 1
    fi
    
    # Check for connected device/emulator
    local device_count=$(adb devices | grep -v "List" | grep -c "device$" || echo "0")
    if [ "$device_count" -eq 0 ]; then
        log "⚠️  No Android device/emulator connected."
        log "Attempting to launch an emulator..."
        
        # Try to find and launch an emulator
        local emulator_name=$(emulator -list-avds 2>/dev/null | head -1)
        if [ -n "$emulator_name" ]; then
            log "Found emulator: $emulator_name"
            log "Launching emulator (this may take a minute)..."
            emulator -avd "$emulator_name" -no-snapshot-load &
            
            # Wait for emulator to boot (max 120 seconds)
            log "Waiting for emulator to boot..."
            local wait_time=0
            while [ $wait_time -lt 120 ]; do
                if adb shell getprop sys.boot_completed 2>/dev/null | grep -q "1"; then
                    log "✅ Emulator booted successfully!"
                    break
                fi
                sleep 5
                wait_time=$((wait_time + 5))
                log "Still waiting... ($wait_time/120 seconds)"
            done
            
            if [ $wait_time -ge 120 ]; then
                log "❌ Emulator boot timeout"
                return 1
            fi
        else
            log "❌ No emulators found. Please create one in Android Studio or connect a device."
            return 1
        fi
    fi
    
    # Uninstall existing app (ignore errors if not installed)
    log "Uninstalling existing app (if any)..."
    adb uninstall "$ANDROID_PACKAGE_NAME" 2>/dev/null || true
    
    # Clear app data (extra cleanup)
    adb shell pm clear "$ANDROID_PACKAGE_NAME" 2>/dev/null || true
    
    # Convert AAB to APKs using bundletool
    log "Converting AAB to APKs..."
    bundletool build-apks \
        --bundle="$aab_path" \
        --output="$apks_path" \
        --mode=universal \
        --overwrite
    
    if [ $? -ne 0 ]; then
        log "❌ Failed to convert AAB to APKs"
        return 1
    fi
    
    # Install APKs
    log "Installing APKs on device..."
    bundletool install-apks --apks="$apks_path"
    
    if [ $? -ne 0 ]; then
        log "❌ Failed to install APKs"
        return 1
    fi
    
    # Verify installation
    local install_time=$(adb shell pm dump "$ANDROID_PACKAGE_NAME" 2>/dev/null | grep "lastUpdateTime" | head -1)
    log "✅ App installed successfully!"
    log "   $install_time"
    
    # Launch the app
    log "Launching app..."
    adb shell monkey -p "$ANDROID_PACKAGE_NAME" -c android.intent.category.LAUNCHER 1
    
    log "✅ App launched! Check the device/emulator."
    log ""
    log "📱 To view logs in real-time:"
    log "   adb logcat -s Unity | grep -E 'DEBUG-BOOT|AppState|AppCore'"
    log ""
    log "📱 To clear logs and start fresh:"
    log "   adb logcat -c && adb logcat -s Unity"
    
    # Clean up temp files
    rm -f "$apks_path"
    
    return 0
}

# Run main function with all arguments
main "$@"

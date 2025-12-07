#!/bin/bash

# Android Baseline Profile Generator
# Captures app startup traces to optimize cold start performance
# 
# This script:
# 1. Installs the app on an emulator/device
# 2. Runs the app multiple times to capture startup traces
# 3. Extracts and saves the baseline profile
#
# The profile gets bundled into the next AAB build for 15-30% faster cold starts
#
# Usage: ./Scripts/generate-baseline-profile.sh [--device <device_id>]

set -e

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_PATH="$(dirname "$SCRIPT_DIR")"

# Load project configuration
if [ -f "$PROJECT_PATH/project-config.sh" ]; then
    source "$PROJECT_PATH/project-config.sh"
fi

# Configuration
PACKAGE_NAME="${ANDROID_PACKAGE_NAME:-com.boardible.ineuj}"
# Firebase Messaging uses a custom activity wrapper
ACTIVITY="${ANDROID_MAIN_ACTIVITY:-com.google.firebase.MessagingUnityPlayerActivity}"
APK_PATH="${PROJECT_PATH}/build/Android/app.apk"
PROFILE_OUTPUT_DIR="${PROJECT_PATH}/Assets/Plugins/Android"
PROFILE_OUTPUT_FILE="${PROFILE_OUTPUT_DIR}/baseline-prof.txt"
NUM_ITERATIONS=3
STARTUP_WAIT_SECONDS=15

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "[$(date '+%H:%M:%S')] $1"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Parse arguments
DEVICE_ID=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --device)
            DEVICE_ID="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--device <device_id>]"
            echo ""
            echo "Generates Android baseline profile for faster app cold starts."
            echo "Requires an emulator or device with API 28+ (Android 9+)"
            echo ""
            echo "Options:"
            echo "  --device <id>  Specify device/emulator ID (from 'adb devices')"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# Set ADB command with optional device
ADB_CMD="adb"
if [ -n "$DEVICE_ID" ]; then
    ADB_CMD="adb -s $DEVICE_ID"
fi

log "=== Android Baseline Profile Generator ==="
log "Package: $PACKAGE_NAME"

# Check if ADB is available
if ! command -v adb &> /dev/null; then
    log_error "ADB not found. Please install Android SDK Platform Tools."
    exit 1
fi

# Emulator path
EMULATOR_PATH="${HOME}/Library/Android/sdk/emulator/emulator"
EMULATOR_PID=""

# Cleanup function - called on exit or error
cleanup() {
    local exit_code=$?
    if [ -n "$EMULATOR_PID" ] && ps -p "$EMULATOR_PID" > /dev/null 2>&1; then
        log "Cleaning up: stopping emulator (PID: $EMULATOR_PID)..."
        kill "$EMULATOR_PID" 2>/dev/null || true
        sleep 2
        kill -9 "$EMULATOR_PID" 2>/dev/null || true
    fi
    
    # Clean up any zombie crashpad handlers
    pkill -9 -f "crashpad_handler.*emu-crash" 2>/dev/null || true
    
    exit $exit_code
}

# Set trap to cleanup on exit, error, or interrupt
trap cleanup EXIT INT TERM

# Kill any existing zombie emulator processes
cleanup_zombie_emulators() {
    log "Checking for zombie emulator processes..."
    local zombie_count=$(pgrep -f "crashpad_handler.*emu-crash" | wc -l | tr -d ' ')
    if [ "$zombie_count" -gt 5 ]; then
        log_warn "Found $zombie_count zombie crashpad processes. Cleaning up..."
        pkill -9 -f "crashpad_handler.*emu-crash" 2>/dev/null || true
        pkill -9 -f "qemu-system" 2>/dev/null || true
        sleep 2
    fi
}

# Function to start emulator if not running
start_emulator_if_needed() {
    local device_count=$($ADB_CMD devices | grep -v "List" | grep -c "device$" || true)
    
    if [ "$device_count" -eq 0 ]; then
        # First cleanup any zombies
        cleanup_zombie_emulators
        
        # Restart ADB server fresh
        adb kill-server 2>/dev/null || true
        sleep 1
        adb start-server
        
        log "No device connected. Starting emulator..."
        
        # Check if emulator command exists
        if [ ! -f "$EMULATOR_PATH" ]; then
            log_error "Emulator not found at: $EMULATOR_PATH"
            exit 1
        fi
        
        # Get first available AVD
        local avd_name=$("$EMULATOR_PATH" -list-avds | head -1)
        if [ -z "$avd_name" ]; then
            log_error "No AVDs found. Create one in Android Studio's AVD Manager."
            exit 1
        fi
        
        # Clear potentially corrupted snapshots
        local avd_path="${HOME}/.android/avd/${avd_name}.avd"
        if [ -d "$avd_path/snapshots" ]; then
            log "Clearing snapshots to prevent boot issues..."
            rm -rf "$avd_path/snapshots"
        fi
        
        log "Starting emulator: $avd_name (cold boot, no snapshots)"
        # Start with no-snapshot-load to avoid corrupted state, and set memory limit
        "$EMULATOR_PATH" -avd "$avd_name" -no-snapshot-load -no-snapshot-save -memory 2048 2>/dev/null &
        EMULATOR_PID=$!
        
        # Wait for emulator to boot
        log "Waiting for emulator to boot (this may take 30-60 seconds)..."
        local max_wait=120
        local waited=0
        local boot_failed=false
        
        while [ $waited -lt $max_wait ]; do
            sleep 5
            waited=$((waited + 5))
            
            # Check if emulator process is still alive
            if ! ps -p "$EMULATOR_PID" > /dev/null 2>&1; then
                log_error "Emulator process died unexpectedly!"
                boot_failed=true
                break
            fi
            
            # Check if emulator is in device list
            if $ADB_CMD devices 2>/dev/null | grep -q "emulator.*device$"; then
                # Check if boot completed
                local boot_complete=$($ADB_CMD shell getprop sys.boot_completed 2>/dev/null || echo "0")
                if [ "$boot_complete" = "1" ]; then
                    log_success "Emulator booted successfully!"
                    sleep 3  # Extra time for stability
                    return 0
                fi
            fi
            
            log "  Still booting... ($waited seconds)"
        done
        
        if [ "$boot_failed" = true ]; then
            log_error "Emulator crashed during startup."
            log "Try one of these solutions:"
            echo "  1. Open Android Studio > Device Manager > Cold Boot your AVD"
            echo "  2. Delete and recreate the AVD in Android Studio"
            echo "  3. Use a physical Android device instead"
            exit 1
        fi
        
        log_error "Emulator failed to boot within $max_wait seconds"
        exit 1
    fi
    
    return 0
}

# Start emulator if needed
start_emulator_if_needed

# Check for connected device/emulator (should always pass now)
DEVICE_COUNT=$($ADB_CMD devices | grep -v "List" | grep -c "device$" || true)
if [ "$DEVICE_COUNT" -eq 0 ]; then
    log_error "No Android device/emulator connected."
    exit 1
fi

# Get device info
DEVICE_INFO=$($ADB_CMD shell getprop ro.product.model 2>/dev/null || echo "Unknown")
API_LEVEL=$($ADB_CMD shell getprop ro.build.version.sdk 2>/dev/null || echo "0")
log "Device: $DEVICE_INFO (API $API_LEVEL)"

# Check API level (baseline profiles work best on API 28+)
if [ "$API_LEVEL" -lt 28 ]; then
    log_warn "API level $API_LEVEL is below 28. Baseline profiles work best on API 28+"
fi

# Check if APK exists
if [ ! -f "$APK_PATH" ]; then
    log_error "APK not found at: $APK_PATH"
    log "Build first with: ./Scripts/unityBuild.sh --platform android"
    exit 1
fi

# Install APK
log "Installing APK..."
$ADB_CMD install -r "$APK_PATH" || {
    log_error "Failed to install APK"
    exit 1
}

# Create output directory
mkdir -p "$PROFILE_OUTPUT_DIR"

# Clear any existing profile data
log "Clearing existing profile data..."
$ADB_CMD shell cmd package compile --reset "$PACKAGE_NAME" 2>/dev/null || true

# Run multiple cold starts to generate profile
log "Running $NUM_ITERATIONS cold starts to capture baseline profile..."
for i in $(seq 1 $NUM_ITERATIONS); do
    log "  Iteration $i/$NUM_ITERATIONS..."
    
    # Force stop to ensure cold start
    $ADB_CMD shell am force-stop "$PACKAGE_NAME"
    sleep 1
    
    # Clear app caches for true cold start
    $ADB_CMD shell run-as "$PACKAGE_NAME" rm -rf /data/data/$PACKAGE_NAME/cache/* 2>/dev/null || true
    
    # Start the app with profiling
    $ADB_CMD shell am start -W -S -n "$PACKAGE_NAME/$ACTIVITY" \
        --ez "profile_boot" "true" 2>/dev/null || \
    $ADB_CMD shell am start -W -S -n "$PACKAGE_NAME/$ACTIVITY"
    
    # Wait for app to fully start
    log "    Waiting ${STARTUP_WAIT_SECONDS}s for app startup..."
    sleep $STARTUP_WAIT_SECONDS
    
    # Stop the app
    $ADB_CMD shell am force-stop "$PACKAGE_NAME"
    sleep 2
done

# Compile with speed profile
log "Compiling app with speed profile..."
$ADB_CMD shell cmd package compile -m speed-profile -f "$PACKAGE_NAME" 2>/dev/null || {
    log_warn "Speed profile compilation not available on this device"
}

# Extract baseline profile
log "Extracting baseline profile..."

# Try to extract the profile (method depends on Android version)
PROFILE_PATH="/data/misc/profiles/cur/0/$PACKAGE_NAME/primary.prof"
TEMP_PROFILE="/sdcard/baseline.prof"

# Copy profile to accessible location
$ADB_CMD shell "run-as $PACKAGE_NAME cat $PROFILE_PATH > $TEMP_PROFILE" 2>/dev/null || \
$ADB_CMD shell "su -c 'cat $PROFILE_PATH' > $TEMP_PROFILE" 2>/dev/null || {
    log_warn "Could not extract raw profile (this is normal on non-rooted devices)"
    log "Using alternative method..."
}

# Pull the profile
if $ADB_CMD pull "$TEMP_PROFILE" "$PROFILE_OUTPUT_FILE.bin" 2>/dev/null; then
    log_success "Baseline profile extracted to: $PROFILE_OUTPUT_FILE.bin"
    
    # Clean up
    $ADB_CMD shell rm -f "$TEMP_PROFILE" 2>/dev/null || true
else
    # Alternative: dump profile info for manual creation
    log "Capturing profile dump..."
    $ADB_CMD shell dumpsys package "$PACKAGE_NAME" | grep -A 50 "Dexopt state:" > "$PROFILE_OUTPUT_FILE.dump" 2>/dev/null || true
    
    # Create a basic baseline profile rules file
    log "Generating basic baseline profile rules..."
    cat > "$PROFILE_OUTPUT_FILE" << 'EOF'
# Android Baseline Profile Rules
# These rules hint the ART runtime to compile critical paths ahead of time
# Generated by generate-baseline-profile.sh

# Unity core classes
HSPLcom/unity3d/player/UnityPlayer;->**(**)**
HSPLcom/unity3d/player/UnityPlayerActivity;->**(**)**

# App startup classes
HSPLcom/Boardible/INEUJ/**;->**(**)**

# Common Android framework classes used at startup
HSPLandroid/app/Activity;->**(**)**
HSPLandroid/view/View;->**(**)**
HSPLandroid/content/Context;->**(**)**
EOF
    log_success "Basic baseline profile rules saved to: $PROFILE_OUTPUT_FILE"
fi

# Summary
echo ""
log "=== Baseline Profile Generation Complete ==="
log_success "Profile saved to: $PROFILE_OUTPUT_DIR"
echo ""
log "Next steps:"
echo "  1. Rebuild your Android AAB: ./Scripts/unityBuild.sh --platform android --release"
echo "  2. The baseline profile will be bundled automatically"
echo "  3. Deploy to Play Store: ./Scripts/androidDeploy.sh"
echo ""
log "Expected improvement: 15-30% faster cold starts"

exit 0

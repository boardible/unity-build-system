#!/bin/bash

# Android Testing & Baseline Profile Script
# Handles: AAB conversion, fresh install, baseline profile generation, launch, and log capture
# Baseline profile generation is MANDATORY for Android builds to ensure cold start optimization

set -e

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_PATH="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ✅ $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ⚠️  $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ❌ $1"
}

# Load configuration
if [ -f "$PROJECT_PATH/project-config.sh" ]; then
    source "$PROJECT_PATH/project-config.sh"
fi

if [ -f "$SCRIPT_DIR/.env.android.local" ]; then
    source "$SCRIPT_DIR/.env.android.local"
fi

# Configuration
PACKAGE_NAME="${ANDROID_PACKAGE_NAME:-com.boardible.ineuj}"
BUILD_OUTPUT_PATH="${BUILD_OUTPUT_PATH:-build}"
ANDROID_BUILD_PATH="$PROJECT_PATH/$BUILD_OUTPUT_PATH/Android"
AAB_PATH="$ANDROID_BUILD_PATH/app.aab"
APK_PATH="$ANDROID_BUILD_PATH/app.apk"
APKS_PATH="$ANDROID_BUILD_PATH/app.apks"
BASELINE_PROFILE_OUTPUT="$PROJECT_PATH/Assets/Plugins/Android/baselineProfiles"
LOG_FILE="$PROJECT_PATH/Logs/android_test_$(date +%Y%m%d_%H%M%S).log"
ACTIVITY_NAME="com.google.firebase.MessagingUnityPlayerActivity"

# Parse arguments
SKIP_BASELINE=false
QUICK_TEST=false
LOG_DURATION=15

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-baseline)
            SKIP_BASELINE=true
            shift
            ;;
        --quick)
            QUICK_TEST=true
            LOG_DURATION=5
            shift
            ;;
        --duration)
            LOG_DURATION="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --skip-baseline    Skip baseline profile generation (NOT recommended)"
            echo "  --quick            Quick test mode (5s logs instead of 15s)"
            echo "  --duration <sec>   Custom log capture duration"
            echo "  -h, --help         Show this help"
            echo ""
            echo "Baseline profile generation is MANDATORY by default."
            echo "It ensures optimal cold start performance on user devices."
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log "=== Android Test & Baseline Profile Generator ==="
log "Package: $PACKAGE_NAME"

# ============================================================================
# PREREQUISITES CHECK
# ============================================================================

# Check adb
if ! command -v adb &> /dev/null; then
    log_error "adb not found. Please install Android SDK Platform-Tools"
    log_error "Install via: brew install --cask android-platform-tools"
    exit 1
fi

# Check bundletool
if ! command -v bundletool &> /dev/null; then
    log_error "bundletool not found. Install with: brew install bundletool"
    exit 1
fi

# Check AAB exists
if [ ! -f "$AAB_PATH" ]; then
    log_error "AAB file not found at $AAB_PATH"
    log "Please run: ./Scripts/unityBuild.sh --platform android"
    exit 1
fi

# Check keystore configuration
if [ -z "$ANDROID_KEYSTORE_PATH" ] || [ -z "$ANDROID_KEYSTORE_PASS" ]; then
    log_error "Keystore configuration missing."
    log "Please set in Scripts/.env.android.local:"
    log "  ANDROID_KEYSTORE_PATH=/path/to/keystore"
    log "  ANDROID_KEYSTORE_PASS=your_password"
    log "  ANDROID_KEY_ALIAS=your_alias"
    log "  ANDROID_KEY_PASS=your_key_password"
    exit 1
fi

# ============================================================================
# DEVICE/EMULATOR DETECTION
# ============================================================================

find_emulator() {
    local EMULATOR_PATHS=(
        "$ANDROID_SDK_ROOT/emulator/emulator"
        "$ANDROID_HOME/emulator/emulator"
        "$HOME/Library/Android/sdk/emulator/emulator"
        "/usr/local/share/android-commandlinetools/emulator/emulator"
    )
    
    for path in "${EMULATOR_PATHS[@]}"; do
        if [ -x "$path" ]; then
            echo "$path"
            return 0
        fi
    done
    
    if command -v emulator &> /dev/null; then
        echo "emulator"
        return 0
    fi
    
    return 1
}

launch_emulator() {
    local EMULATOR_CMD=$(find_emulator)
    
    if [ -z "$EMULATOR_CMD" ]; then
        log_error "Emulator not found. Please set ANDROID_SDK_ROOT or install Android SDK."
        return 1
    fi
    
    local AVDS=$("$EMULATOR_CMD" -list-avds 2>/dev/null)
    
    if [ -z "$AVDS" ]; then
        log_error "No Android Virtual Devices (AVDs) found."
        log "Please create one in Android Studio: Tools → Device Manager → Create Device"
        return 1
    fi
    
    local AVD_NAME=$(echo "$AVDS" | head -n 1)
    log "Found emulator: $AVD_NAME"
    log "Launching emulator..."
    
    "$EMULATOR_CMD" -avd "$AVD_NAME" -no-snapshot-load &
    
    log "Waiting for emulator to boot..."
    local BOOT_TIMEOUT=120
    local WAIT_TIME=0
    
    while [ $WAIT_TIME -lt $BOOT_TIMEOUT ]; do
        if adb shell getprop sys.boot_completed 2>/dev/null | grep -q "1"; then
            log_success "Emulator booted!"
            sleep 5
            return 0
        fi
        sleep 5
        WAIT_TIME=$((WAIT_TIME + 5))
        log "Still waiting... ($WAIT_TIME/$BOOT_TIMEOUT seconds)"
    done
    
    log_error "Emulator boot timeout"
    return 1
}

if ! adb devices | grep -q "device$"; then
    log_warning "No Android device connected"
    log "Attempting to launch an emulator..."
    
    if ! launch_emulator; then
        log_error "Could not launch emulator."
        log "Please connect a device or start an emulator manually."
        exit 1
    fi
fi

log_success "Android device detected"

# ============================================================================
# APK EXTRACTION FROM AAB
# ============================================================================

log "Converting AAB to APK..."
rm -f "$APK_PATH" "$APKS_PATH"
rm -rf "$ANDROID_BUILD_PATH/temp_apks"

bundletool build-apks \
    --bundle="$AAB_PATH" \
    --output="$APKS_PATH" \
    --mode=universal \
    --ks="$ANDROID_KEYSTORE_PATH" \
    --ks-pass="pass:$ANDROID_KEYSTORE_PASS" \
    --ks-key-alias="${ANDROID_KEY_ALIAS:-uploadkey}" \
    --key-pass="pass:${ANDROID_KEY_PASS:-$ANDROID_KEYSTORE_PASS}"

unzip -q -o "$APKS_PATH" -d "$ANDROID_BUILD_PATH/temp_apks"
mv "$ANDROID_BUILD_PATH/temp_apks/universal.apk" "$APK_PATH"
rm -rf "$ANDROID_BUILD_PATH/temp_apks" "$APKS_PATH"

log_success "APK generated: $APK_PATH"

# ============================================================================
# FRESH INSTALL
# ============================================================================

log "Uninstalling old version..."
adb uninstall "$PACKAGE_NAME" 2>/dev/null || true

log "Installing new version..."
adb install -r "$APK_PATH"

log_success "App installed"

# ============================================================================
# BASELINE PROFILE GENERATION (MANDATORY)
# ============================================================================

if [ "$SKIP_BASELINE" = false ]; then
    log ""
    log "=== Baseline Profile Generation ==="
    log "This optimizes cold start time by ~15-30%"
    log ""
    
    # Clear app data for clean profile
    log "Clearing app data for clean profile..."
    adb shell pm clear "$PACKAGE_NAME"
    
    # Compile with speed-profile mode
    log "Compiling with speed-profile instrumentation..."
    adb shell cmd package compile -f -m speed-profile "$PACKAGE_NAME"
    
    # Launch app
    log "Launching app for profile collection..."
    adb shell monkey -p "$PACKAGE_NAME" -c android.intent.category.LAUNCHER 1
    
    log ""
    log "📱 Please interact with the app:"
    log "   1. Wait for splash screen to finish"
    log "   2. Navigate through main menu"
    log "   3. Start a game and play for ~30 seconds"
    log ""
    read -p "Press Enter when done interacting with the app..."
    
    # Stop app to flush profile
    log "Stopping app to flush profile..."
    adb shell am force-stop "$PACKAGE_NAME"
    sleep 2
    
    # Extract profile
    log "Extracting baseline profile..."
    
    PROFILE_PATHS=(
        "/data/misc/profiles/cur/0/$PACKAGE_NAME/primary.prof"
        "/data/misc/profiles/ref/$PACKAGE_NAME/primary.prof"
    )
    
    PROFILE_FOUND=false
    TEMP_PROFILE="/tmp/baseline-profile-${PACKAGE_NAME}.prof"
    
    for PROFILE_PATH in "${PROFILE_PATHS[@]}"; do
        if adb shell "test -f $PROFILE_PATH && echo exists" 2>/dev/null | grep -q exists; then
            log "Found profile at: $PROFILE_PATH"
            adb pull "$PROFILE_PATH" "$TEMP_PROFILE" && PROFILE_FOUND=true && break
        fi
    done
    
    if [ "$PROFILE_FOUND" = true ]; then
        mkdir -p "$BASELINE_PROFILE_OUTPUT"
        BINARY_OUTPUT="$BASELINE_PROFILE_OUTPUT/baseline-prof.prof"
        cp "$TEMP_PROFILE" "$BINARY_OUTPUT"
        rm -f "$TEMP_PROFILE"
        
        log_success "Baseline profile saved: $BINARY_OUTPUT"
        log "Profile will be included in next AAB build."
    else
        log_warning "Could not extract baseline profile (Android 9+ required)"
        log_warning "Continuing without profile optimization..."
    fi
else
    log_warning "Skipping baseline profile generation (--skip-baseline)"
    log_warning "Cold start performance may be suboptimal!"
fi

# ============================================================================
# APP LAUNCH & LOG CAPTURE
# ============================================================================

log ""
log "=== App Launch & Log Capture ==="

# Clear app data again for fresh test
log "Clearing app data for fresh test..."
adb shell pm clear "$PACKAGE_NAME" 2>/dev/null || true

# Clear logcat
adb logcat -c

# Launch app
log "Launching app..."
adb shell am start -n "$PACKAGE_NAME/$ACTIVITY_NAME"

# Capture logs
log "Capturing logs for $LOG_DURATION seconds..."
mkdir -p "$(dirname "$LOG_FILE")"

adb logcat -v time > "$LOG_FILE" &
LOGCAT_PID=$!

sleep "$LOG_DURATION"

kill "$LOGCAT_PID" 2>/dev/null || true

# ============================================================================
# RESULTS
# ============================================================================

log ""
log "=== Test Results ==="
log "Logs saved to: $LOG_FILE"
log ""

# Show relevant log entries
log "Boot sequence:"
grep -E "DEBUG-BOOT|AppCore|AppState|BootState" "$LOG_FILE" 2>/dev/null | head -20 || echo "(no boot logs found)"

log ""
log "Errors/Exceptions:"
grep -iE "Exception|Error|Fatal|Crash" "$LOG_FILE" 2>/dev/null | grep -v "no error" | head -10 || echo "(no errors found)"

log ""
log_success "Test completed!"
log ""
log "📱 Quick commands:"
log "   View full logs:  cat $LOG_FILE"
log "   Live logs:       adb logcat -s Unity | grep -E 'DEBUG-BOOT|AppState'"
log "   Clear & restart: adb shell pm clear $PACKAGE_NAME && adb shell am start -n $PACKAGE_NAME/$ACTIVITY_NAME"

exit 0

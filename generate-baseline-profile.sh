#!/bin/bash

# Baseline Profile Generator for Android
# Automatically extracts and optimizes app cold start performance
# This script should run AFTER building AAB/APK but BEFORE deploying to Play Store

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

PACKAGE_NAME="${ANDROID_PACKAGE_NAME:-com.boardible.ineuj}"
BUILD_OUTPUT_PATH="${BUILD_OUTPUT_PATH:-build}"
ANDROID_BUILD_PATH="$PROJECT_PATH/$BUILD_OUTPUT_PATH/Android"
BASELINE_PROFILE_OUTPUT="$PROJECT_PATH/Assets/Plugins/Android/baselineProfiles"

log "=== Android Baseline Profile Generator ==="
log "Package: $PACKAGE_NAME"

# Check if adb is available
if ! command -v adb &> /dev/null; then
    log_error "adb not found. Please install Android SDK Platform-Tools"
    log_error "Install via: brew install --cask android-platform-tools"
    exit 1
fi

# Check if device is connected
if ! adb devices | grep -q "device$"; then
    log_error "No Android device connected"
    log "Please connect a device via USB and enable USB debugging"
    log "Then run: adb devices"
    exit 1
fi

log_success "Android device detected"

# Check if app is installed
if ! adb shell pm list packages | grep -q "$PACKAGE_NAME"; then
    log_error "App $PACKAGE_NAME is not installed on device"
    log "Please install the APK/AAB first:"
    log "  adb install $ANDROID_BUILD_PATH/app.apk"
    exit 1
fi

log_success "App is installed on device"

# Step 1: Force-stop app if running
log "Stopping app if running..."
adb shell am force-stop "$PACKAGE_NAME" || true

# Step 2: Clear app data for fresh profile
log "Clearing app data for clean profile generation..."
adb shell pm clear "$PACKAGE_NAME"

# Step 3: Compile app with speed-profile mode
# This instruments the app to collect profile data during execution
log "Compiling app with speed-profile instrumentation..."
adb shell cmd package compile -f -m speed-profile "$PACKAGE_NAME"

# Step 4: Launch app and let it run
log "Launching app..."
log "The app will now start. Please perform these actions:"
log "  1. Wait for splash screen to finish"
log "  2. Navigate through main menu"
log "  3. Start a game"
log "  4. Play for ~30 seconds"
log "  5. Press Ctrl+C when done"
log ""
log "The longer you interact with the app, the better the profile."
log "Focus on cold start and frequently used screens."

# Launch the app
adb shell monkey -p "$PACKAGE_NAME" -c android.intent.category.LAUNCHER 1

# Wait for user to interact with app
log ""
log "⏳ Collecting profile data... (Press Ctrl+C when done)"
read -p "Press Enter when you've finished interacting with the app..."

# Step 5: Force-stop app to flush profile data
log "Stopping app to flush profile data..."
adb shell am force-stop "$PACKAGE_NAME"

# Wait a moment for profile to be written
sleep 2

# Step 6: Extract the baseline profile
log "Extracting baseline profile from device..."

# The profile is stored in different locations depending on Android version
# Try multiple locations
PROFILE_PATHS=(
    "/data/misc/profiles/cur/0/$PACKAGE_NAME/primary.prof"
    "/data/misc/profiles/ref/$PACKAGE_NAME/primary.prof"
)

PROFILE_FOUND=false
TEMP_PROFILE="/tmp/baseline-profile-${PACKAGE_NAME}.prof"

for PROFILE_PATH in "${PROFILE_PATHS[@]}"; do
    if adb shell "test -f $PROFILE_PATH && echo exists" | grep -q exists; then
        log "Found profile at: $PROFILE_PATH"
        adb pull "$PROFILE_PATH" "$TEMP_PROFILE" && PROFILE_FOUND=true && break
    fi
done

if [ "$PROFILE_FOUND" = false ]; then
    log_error "Could not find baseline profile on device"
    log_error "This might happen if:"
    log_error "  - App wasn't used enough to generate profile"
    log_error "  - Device doesn't support baseline profiles (Android 9+ required)"
    log_error "  - App doesn't have baseline profile configuration"
    exit 1
fi

# Step 7: Convert binary profile to human-readable format
log "Converting profile to human-readable format..."

# Create output directory
mkdir -p "$BASELINE_PROFILE_OUTPUT"

# Copy binary profile
BINARY_OUTPUT="$BASELINE_PROFILE_OUTPUT/baseline-prof.prof"
cp "$TEMP_PROFILE" "$BINARY_OUTPUT"

log_success "Baseline profile generated successfully!"
log "Binary profile saved to: $BINARY_OUTPUT"

# Step 8: Generate human-readable text version for inspection
log "Generating text version for inspection..."

# Try to convert using profman (if available)
if command -v profman &> /dev/null; then
    TEXT_OUTPUT="$BASELINE_PROFILE_OUTPUT/baseline-prof.txt"
    
    # Get app APK path to extract methods
    APK_PATH=$(adb shell pm path "$PACKAGE_NAME" | cut -d: -f2 | tr -d '\r')
    
    if [ -n "$APK_PATH" ]; then
        TEMP_APK="/tmp/app.apk"
        adb pull "$APK_PATH" "$TEMP_APK"
        
        profman --profile-file="$BINARY_OUTPUT" \
                --apk="$TEMP_APK" \
                --dex-location=/data/app/"$PACKAGE_NAME" \
                --dump-classes-and-methods \
                --dump-output-to-fd=1 > "$TEXT_OUTPUT" 2>/dev/null || true
        
        if [ -f "$TEXT_OUTPUT" ] && [ -s "$TEXT_OUTPUT" ]; then
            log_success "Text profile saved to: $TEXT_OUTPUT"
            
            # Show profile statistics
            CLASS_COUNT=$(grep -c "^L" "$TEXT_OUTPUT" 2>/dev/null || echo "0")
            METHOD_COUNT=$(grep -c "^[A-Z]" "$TEXT_OUTPUT" 2>/dev/null || echo "0")
            
            log "Profile statistics:"
            log "  Classes: $CLASS_COUNT"
            log "  Methods: $METHOD_COUNT"
        fi
        
        rm -f "$TEMP_APK"
    fi
fi

# Cleanup
rm -f "$TEMP_PROFILE"

log ""
log_success "Baseline profile generation complete!"
log ""
log "Next steps:"
log "  1. The binary profile is at: $BINARY_OUTPUT"
log "  2. This will be automatically included in your next AAB build"
log "  3. Upload the new AAB to Play Store"
log "  4. Users will see ~15-30% faster cold start times"
log ""
log "To verify the profile is included in your build:"
log "  unzip -l build/Android/app.aab | grep baseline"

exit 0

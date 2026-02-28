#!/bin/bash

# Android Environment Fixer & Setup
# This script ensures Unity's internal Android SDK is correctly configured,
# licenses are accepted, and plugins are updated to compatible SDK versions.

# Intentionally no set -e: this is a best-effort setup step and must never stop the build

# Get script directory and project paths
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_PATH="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}
success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}
warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}
error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# Detect Unity version matching the project
UNITY_VERSION=$(grep "m_EditorVersion:" "$PROJECT_PATH/ProjectSettings/ProjectVersion.txt" | sed 's/m_EditorVersion: //' | tr -d '[:space:]' || echo "6000.3.7f1")

# Unity Android SDK Path
UNITY_SDK_PATH="/Applications/Unity/Hub/Editor/${UNITY_VERSION}/PlaybackEngines/AndroidPlayer/SDK"
UNITY_JAVA_HOME="/Applications/Unity/Hub/Editor/${UNITY_VERSION}/PlaybackEngines/AndroidPlayer/OpenJDK"

if [ ! -d "$UNITY_SDK_PATH" ]; then
    warning "Unity SDK not found at $UNITY_SDK_PATH"
    log "Trying alternative location..."
    UNITY_SDK_PATH="/Applications/Unity/Unity.app/Contents/PlaybackEngines/AndroidPlayer/SDK"
    UNITY_JAVA_HOME="/Applications/Unity/Unity.app/Contents/PlaybackEngines/AndroidPlayer/OpenJDK"
fi

# Step 1: Accept Licenses
log "Step 1: Accepting Android SDK Licenses for Unity's SDK..."
if [ -d "$UNITY_SDK_PATH" ] && [ -d "$UNITY_JAVA_HOME" ]; then
    SDKMANAGER=$(find "$UNITY_SDK_PATH" -name "sdkmanager" | head -n 1)
    if [ -n "$SDKMANAGER" ]; then
        export JAVA_HOME="$UNITY_JAVA_HOME"
        log "Using sdkmanager at: $SDKMANAGER"
        yes | "$SDKMANAGER" --licenses > /dev/null 2>&1 && success "Licenses accepted." || warning "Some licenses could not be auto-accepted (may be already accepted)."
    else
        error "sdkmanager not found in $UNITY_SDK_PATH"
    fi
else
    error "Unity Android Player or OpenJDK not found. Please ensure Android build support is installed."
fi

# Step 2: Install required Build-Tools if missing
# Ineuj uses BuildScript.cs which might expect build-tools 34
log "Step 2: Ensuring Build-Tools 34.0.0 is installed..."
if [ -n "$SDKMANAGER" ]; then
    yes | "$SDKMANAGER" "build-tools;34.0.0" "platforms;android-34" > /dev/null 2>&1 && success "Build-tools 34 and Platform 34 installed/verified." || warning "Build-tools 34 install skipped (already installed or failed)."
fi

# Step 3: Fix .androidlib project.properties
log "Step 3: Updating .androidlib plugins to use modern target SDK..."
# Get Target SDK from ProjectSettings
TARGET_SDK=$(grep "AndroidTargetSdkVersion:" "$PROJECT_PATH/ProjectSettings/ProjectSettings.asset" | sed 's/  AndroidTargetSdkVersion: //' | tr -d '[:space:]' || echo "34")

# List all project.properties files in Android plugins
find "$PROJECT_PATH/Assets/Plugins/Android" -name "project.properties" | while read -r prop_file; do
    if grep -q "target=android-" "$prop_file"; then
        CURRENT_TARGET=$(grep "target=android-" "$prop_file" | sed 's/target=android-//' | tr -d '[:space:]')
        if [ "$CURRENT_TARGET" -lt "$TARGET_SDK" ]; then
            log "  Updating $prop_file (android-$CURRENT_TARGET -> android-$TARGET_SDK)"
            # Use a portable sed (macOS vs Linux)
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s/target=android-$CURRENT_TARGET/target=android-$TARGET_SDK/" "$prop_file"
            else
                sed -i "s/target=android-$CURRENT_TARGET/target=android-$TARGET_SDK/" "$prop_file"
            fi
        fi
    fi
done
success "Plugin project.properties updated to match project Target SDK ($TARGET_SDK)."

log "Android environment verification complete!"

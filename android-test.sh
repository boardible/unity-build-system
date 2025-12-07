#!/bin/bash
# Android First-Install Test Script
# Usage: ./Scripts/android-test.sh [--fresh] [--logs-only]

PACKAGE="com.Boardible.INEUJ"
ACTIVITY="com.unity3d.player.UnityPlayerActivity"
APK_PATH="build/Android/app.apk"

# Parse args
FRESH_INSTALL=false
LOGS_ONLY=false
for arg in "$@"; do
    case $arg in
        --fresh) FRESH_INSTALL=true ;;
        --logs-only) LOGS_ONLY=true ;;
    esac
done

# Check if emulator is running
if ! adb devices | grep -q "emulator"; then
    echo "❌ No emulator running. Start one with:"
    echo "   ~/Library/Android/sdk/emulator/emulator -avd Pixel_8_Pro_API_35 &"
    exit 1
fi

if [ "$LOGS_ONLY" = true ]; then
    echo "📋 Watching logs..."
    adb logcat -c  # Clear old logs
    adb logcat -s Unity | grep --line-buffered -E "DEBUG-BOOT|AppIntro|Load|Error|Exception|video|Video"
    exit 0
fi

# Check APK exists
if [ ! -f "$APK_PATH" ]; then
    echo "❌ APK not found at $APK_PATH"
    echo "   Build first with: ./Scripts/unityBuild.sh --platform android"
    exit 1
fi

echo "📱 Android First-Install Test"
echo "=============================="

if [ "$FRESH_INSTALL" = true ]; then
    echo "🗑️  Clearing app data (simulating fresh install)..."
    adb shell pm clear $PACKAGE 2>/dev/null || true
    adb uninstall $PACKAGE 2>/dev/null || true
fi

echo "📦 Installing APK..."
adb install -r "$APK_PATH"

echo "🧹 Clearing logcat..."
adb logcat -c

echo "🚀 Launching app..."
adb shell am start -n "$PACKAGE/$ACTIVITY"

echo ""
echo "📋 Watching logs (Ctrl+C to stop)..."
echo "======================================"
adb logcat -s Unity | grep --line-buffered -E "DEBUG-BOOT|AppIntro|SetSystemAsBooted|ReInitialize|Load|Error|Exception|video|Video|haptic|Haptic"

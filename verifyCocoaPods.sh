#!/bin/bash

# Quick verification that CocoaPods is accessible for Unity
# Run this to verify the fix worked

echo "=== CocoaPods Accessibility Check ==="
echo

# Check 1: Pod in system PATH
echo "1. Checking pod in PATH..."
if command -v pod &> /dev/null; then
    echo "   ✅ pod found: $(which pod)"
else
    echo "   ❌ pod not found in PATH"
    exit 1
fi

# Check 2: Pod version
echo "2. Checking pod version..."
POD_VERSION=$(pod --version 2>&1)
if [[ $? -eq 0 ]]; then
    echo "   ✅ CocoaPods version: $POD_VERSION"
else
    echo "   ❌ pod command failed"
    echo "$POD_VERSION"
    exit 1
fi

# Check 3: Symlink at /usr/local/bin/pod
echo "3. Checking standard symlink..."
if [[ -L "/usr/local/bin/pod" ]]; then
    TARGET=$(readlink /usr/local/bin/pod)
    echo "   ✅ Symlink exists: /usr/local/bin/pod -> $TARGET"
elif [[ -f "/usr/local/bin/pod" ]]; then
    echo "   ✅ pod exists at /usr/local/bin/pod (direct install)"
else
    echo "   ⚠️  No pod at /usr/local/bin/pod (may be OK if Unity finds it elsewhere)"
fi

# Check 4: iOS Resolver settings
echo "4. Checking iOS Resolver settings..."
SETTINGS_FILE="$(cd "$(dirname "$0")/.." && pwd)/Assets/ExternalDependencyManager/Editor/IOSResolverSettings.xml"
if [[ -f "$SETTINGS_FILE" ]]; then
    POD_PATH=$(grep -o '<cocoapodsToolPath>.*</cocoapodsToolPath>' "$SETTINGS_FILE" | sed 's/<[^>]*>//g')
    echo "   ✅ Settings file exists"
    echo "   ✅ Configured pod path: $POD_PATH"
    
    if [[ -f "$POD_PATH" ]]; then
        echo "   ✅ Pod executable exists at configured path"
    else
        echo "   ❌ Pod executable NOT found at configured path"
        exit 1
    fi
else
    echo "   ⚠️  Settings file not found (will use defaults)"
fi

# Check 5: Ruby and gems
echo "5. Checking Ruby environment..."
RUBY_VERSION=$(ruby --version | awk '{print $2}')
echo "   ✅ Ruby: $RUBY_VERSION"

# Check 6: Test pod search (quick CocoaPods functionality test)
echo "6. Testing pod functionality..."
if timeout 5 pod search Firebase --limit=1 &> /dev/null; then
    echo "   ✅ Pod search works (CocoaPods fully functional)"
elif pod --help &> /dev/null; then
    echo "   ✅ Pod help works (CocoaPods functional, repo may need update)"
else
    echo "   ❌ Pod command not working properly"
    exit 1
fi

echo
echo "=== All Checks Passed ✅ ==="
echo "CocoaPods is properly configured for Unity iOS Resolver"
echo
echo "Next: Restart Unity and test iOS Resolver"

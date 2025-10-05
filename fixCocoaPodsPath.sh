#!/bin/bash

# Script to configure Unity iOS Resolver to find CocoaPods
# Fixes: "pod tool cannot be found" error in Unity

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] $1${NC}"
}

print_success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] $1${NC}"
}

print_error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] $1${NC}"
}

PROJECT_PATH="$(cd "$(dirname "$0")/.." && pwd)"

print_status "=== iOS Resolver CocoaPods Configuration ==="
echo

# Step 1: Find pod executable
print_status "Locating CocoaPods installation..."
POD_PATH=$(which pod 2>/dev/null || echo "")

if [[ -z "$POD_PATH" ]]; then
    print_error "CocoaPods not found in PATH!"
    print_status "Expected locations:"
    echo "  - /usr/local/lib/ruby/gems/3.4.0/bin/pod"
    echo "  - /usr/local/bin/pod"
    echo "  - ~/.gem/ruby/*/bin/pod"
    exit 1
fi

print_success "✓ Found CocoaPods at: $POD_PATH"

# Step 2: Get pod version
POD_VERSION=$(pod --version 2>/dev/null || echo "unknown")
print_success "✓ CocoaPods version: $POD_VERSION"

# Step 3: Get Ruby version
RUBY_VERSION=$(ruby --version | awk '{print $2}')
print_success "✓ Ruby version: $RUBY_VERSION"

# Step 4: Create iOS Resolver settings
print_status "Creating iOS Resolver settings..."

SETTINGS_DIR="$PROJECT_PATH/Assets/ExternalDependencyManager/Editor"
SETTINGS_FILE="$SETTINGS_DIR/IOSResolverSettings.xml"

# Create directory if needed
mkdir -p "$SETTINGS_DIR"

# Create settings file with explicit pod path
cat > "$SETTINGS_FILE" << EOF
<?xml version="1.0" encoding="utf-8"?>
<iosResolverSettings>
  <cocoapodsToolPath>$POD_PATH</cocoapodsToolPath>
  <podfileGenerationEnabled>true</podfileGenerationEnabled>
  <autoPodToolInstallInEditor>false</autoPodToolInstallInEditor>
  <cocoapodsIntegrationMethod>1</cocoapodsIntegrationMethod>
  <useProjectSettings>true</useProjectSettings>
  <verboseLoggingEnabled>false</verboseLoggingEnabled>
</iosResolverSettings>
EOF

print_success "✓ Created iOS Resolver settings"

# Step 5: Add to shell profile for future Unity sessions
print_status "Checking shell configuration..."

SHELL_RC="$HOME/.zshrc"
POD_BIN_DIR=$(dirname "$POD_PATH")

if ! grep -q "$POD_BIN_DIR" "$SHELL_RC" 2>/dev/null; then
    print_warning "CocoaPods bin directory not in shell profile"
    print_status "Adding to $SHELL_RC..."
    
    echo "" >> "$SHELL_RC"
    echo "# CocoaPods (added by fixCocoaPodsPath.sh)" >> "$SHELL_RC"
    echo "export PATH=\"$POD_BIN_DIR:\$PATH\"" >> "$SHELL_RC"
    
    print_success "✓ Added CocoaPods to PATH in $SHELL_RC"
    print_warning "You may need to restart your terminal for this to take effect"
else
    print_success "✓ CocoaPods already in shell profile"
fi

# Step 6: Create symlink fallback (Unity sometimes checks /usr/local/bin)
print_status "Creating symlink fallback..."

if [[ ! -e "/usr/local/bin/pod" ]]; then
    if [[ -w "/usr/local/bin" ]]; then
        ln -sf "$POD_PATH" "/usr/local/bin/pod"
        print_success "✓ Created symlink: /usr/local/bin/pod -> $POD_PATH"
    else
        print_warning "⚠️  Cannot create symlink (need sudo)"
        print_status "Run this if iOS Resolver still fails:"
        echo "  sudo ln -sf $POD_PATH /usr/local/bin/pod"
    fi
else
    print_success "✓ Symlink already exists: /usr/local/bin/pod"
fi

# Step 7: Verify CocoaPods works
print_status "Verifying CocoaPods..."
cd "$PROJECT_PATH"

if pod --version &> /dev/null; then
    print_success "✓ CocoaPods command works from project directory"
else
    print_error "✗ CocoaPods command failed"
    exit 1
fi

echo
print_success "=== Configuration Complete ==="
print_status "Summary:"
echo "  CocoaPods Path: $POD_PATH"
echo "  Version: $POD_VERSION"
echo "  Settings: $SETTINGS_FILE"
echo
print_status "Next steps:"
echo "1. Restart Unity (REQUIRED)"
echo "2. Go to: Assets > External Dependency Manager > iOS Resolver > Settings"
echo "3. Verify settings show:"
echo "   - Cocoapods Integration Method: Xcode Workspace"
echo "   - Pod tool path: $POD_PATH"
echo "4. Click 'Install Cocoapods' or 'Force Resolve'"
echo
print_warning "If error persists after restart, run:"
echo "  sudo ln -sf $POD_PATH /usr/local/bin/pod"

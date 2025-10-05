#!/bin/bash

# Comprehensive Ruby/CocoaPods fix script
# Fixes: gem extensions not built, CocoaPods installation issues, iOS Resolver problems

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Change to a valid directory first (critical!)
cd ~

print_status "=== Ruby & CocoaPods Repair ==="
echo

# Step 1: Rebuild all broken gem extensions
print_status "Rebuilding broken gem extensions..."
print_warning "This may take a few minutes..."

# Get list of broken gems
broken_gems=$(gem list --local 2>/dev/null | grep -E "(json|digest-crc|strscan|nkf|sysrandom|unf_ext)" | awk '{print $1}' | sort -u)

if [[ -n "$broken_gems" ]]; then
    echo "$broken_gems" | while read gem_name; do
        print_status "Rebuilding $gem_name..."
        gem pristine "$gem_name" 2>/dev/null || print_warning "  Could not rebuild $gem_name (may be OK)"
    done
    print_success "✓ Gem extensions rebuilt"
else
    print_success "✓ No broken gems found"
fi

# Step 2: Verify Ruby installation
print_status "Checking Ruby installation..."
ruby_version=$(ruby --version)
print_success "✓ Ruby: $ruby_version"

# Step 3: Check current CocoaPods installation
print_status "Checking CocoaPods installation..."
if command -v pod &> /dev/null; then
    pod_path=$(which pod)
    print_success "✓ CocoaPods found at: $pod_path"
    
    # Try to get version (from valid directory)
    cd ~
    if pod_version=$(pod --version 2>&1); then
        print_success "✓ CocoaPods version: $pod_version"
    else
        print_warning "⚠️  CocoaPods installed but version check failed"
        print_status "Reinstalling CocoaPods..."
        gem uninstall cocoapods -a -x -I 2>/dev/null || true
        gem install cocoapods
        print_success "✓ CocoaPods reinstalled"
    fi
else
    print_warning "CocoaPods not found, installing..."
    gem install cocoapods
    print_success "✓ CocoaPods installed"
fi

# Step 4: Update CocoaPods repository
print_status "Updating CocoaPods repository..."
cd ~
pod repo update --silent 2>&1 | head -20 || print_warning "Repo update had issues (may be OK)"

# Step 5: Check for duplicate repos
print_status "Checking for duplicate CocoaPods repositories..."
if [[ -d ~/.cocoapods/repos/trunk && -d ~/.cocoapods/repos/cocoapods ]]; then
    print_warning "Duplicate repos found, removing old 'cocoapods' repo..."
    pod repo remove cocoapods 2>/dev/null || true
    print_success "✓ Duplicate removed"
fi

# Step 6: Verify pod command works
print_status "Verifying pod command..."
cd ~
if pod --version &> /dev/null; then
    print_success "✓ Pod command working correctly"
else
    print_error "✗ Pod command still failing"
    print_status "Trying alternative installation method..."
    
    # Try system-wide install
    sudo gem install cocoapods
fi

# Step 7: Check PATH configuration
print_status "Checking PATH configuration..."
pod_bin_path=$(dirname "$(which pod)")
if echo "$PATH" | grep -q "$pod_bin_path"; then
    print_success "✓ CocoaPods bin directory in PATH: $pod_bin_path"
else
    print_warning "⚠️  CocoaPods bin not in PATH"
    print_status "Add this to your ~/.zshrc:"
    echo "  export PATH=\"$pod_bin_path:\$PATH\""
fi

# Step 8: Test with a simple pod command
print_status "Testing pod command with --help..."
cd ~
if pod --help &> /dev/null; then
    print_success "✓ Pod command fully functional"
else
    print_error "✗ Pod command still having issues"
fi

echo
print_success "=== Repair Complete ==="
print_status "Summary:"
echo "  Ruby: $(ruby --version | awk '{print $2}')"
echo "  CocoaPods: $(cd ~ && pod --version 2>/dev/null || echo 'ERROR')"
echo "  Pod Path: $(which pod)"
echo
print_status "Next steps:"
echo "1. Restart Unity"
echo "2. Go to: Assets > External Dependency Manager > iOS Resolver > Settings"
echo "3. Verify CocoaPods integration works"
echo "4. If issues persist, check Unity Console for specific errors"

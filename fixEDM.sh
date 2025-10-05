#!/bin/bash

# Script to fix External Dependency Manager (EDM) installation
# Resolves: System.MissingMethodExceptio# Step 7: Summary
echo
print_success "=== EDM Cleanup Complete ==="
print_status "What was fixed:"
echo "  • Removed old EDM 1.2.166 from Assets (conflicting with 1.2.182)"
echo "  • Cleared Unity cache and assemblies"
echo "  • Refreshed EDM 1.2.186 in Package Manager"
echo
print_status "Next steps:"
echo "1. Open Unity"
echo "2. Wait for package resolution to complete"
echo "3. Check Console for any errors"
echo "4. Test iOS Resolver: Assets > External Dependency Manager > iOS Resolver > Settings"
echo
print_warning "If the error persists, the issue might be in the CommandLine DLL itself"
print_status "Backup saved: Packages/manifest.json.backup"olver

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

# Get project path
PROJECT_PATH="$(cd "$(dirname "$0")/.." && pwd)"

print_status "=== EDM Cleanup & Reinstall ==="
print_status "Project: $PROJECT_PATH"
echo

# Step 1: Close Unity if running
print_warning "Please close Unity before continuing!"
read -p "Press Enter once Unity is closed..."

# Step 2: Remove old EDM versions from Assets
print_status "Checking for conflicting EDM installations in Assets..."
if [[ -d "$PROJECT_PATH/Assets/ExternalDependencyManager" ]]; then
    print_warning "Found EDM in Assets folder (this causes conflicts with Package Manager version)"
    print_status "Removing old EDM versions: 1.2.166..."
    
    # Remove old version 1.2.166
    if [[ -d "$PROJECT_PATH/Assets/ExternalDependencyManager/Editor/1.2.166" ]]; then
        rm -rf "$PROJECT_PATH/Assets/ExternalDependencyManager/Editor/1.2.166"
        rm -f "$PROJECT_PATH/Assets/ExternalDependencyManager/Editor/1.2.166.meta"
        print_success "✓ Removed EDM 1.2.166"
    fi
    
    # Remove old manifest files
    if [[ -f "$PROJECT_PATH/Assets/ExternalDependencyManager/Editor/external-dependency-manager_version-1.2.166_manifest.txt" ]]; then
        rm -f "$PROJECT_PATH/Assets/ExternalDependencyManager/Editor/external-dependency-manager_version-1.2.166_manifest.txt"
        rm -f "$PROJECT_PATH/Assets/ExternalDependencyManager/Editor/external-dependency-manager_version-1.2.166_manifest.txt.meta"
        print_success "✓ Removed old manifest files"
    fi
else
    print_success "✓ No conflicting EDM installations in Assets"
fi

# Step 3: Clean Unity Library cache
print_status "Cleaning Unity Library cache..."
if [[ -d "$PROJECT_PATH/Library/ScriptAssemblies" ]]; then
    rm -rf "$PROJECT_PATH/Library/ScriptAssemblies"
    print_success "✓ Cleared ScriptAssemblies"
fi

if [[ -d "$PROJECT_PATH/Library/PackageCache/com.google.external-dependency-manager@"* ]]; then
    rm -rf "$PROJECT_PATH/Library/PackageCache/com.google.external-dependency-manager@"*
    print_success "✓ Cleared EDM package cache"
fi

# Step 3: Clean Unity Library cache
print_status "Cleaning Unity Library cache..."
if [[ -d "$PROJECT_PATH/Library/ScriptAssemblies" ]]; then
    rm -rf "$PROJECT_PATH/Library/ScriptAssemblies"
    print_success "✓ Cleared ScriptAssemblies"
fi

if [[ -d "$PROJECT_PATH/Library/PackageCache/com.google.external-dependency-manager@"* ]]; then
    rm -rf "$PROJECT_PATH/Library/PackageCache/com.google.external-dependency-manager@"*
    print_success "✓ Cleared EDM package cache"
fi

# Step 4: Remove EDM from manifest temporarily
print_status "Temporarily removing EDM from manifest..."
cp "$PROJECT_PATH/Packages/manifest.json" "$PROJECT_PATH/Packages/manifest.json.backup"

# Remove EDM line (macOS sed syntax)
sed -i '' '/com.google.external-dependency-manager/d' "$PROJECT_PATH/Packages/manifest.json"
print_success "✓ EDM removed from manifest (backup created)"

# Step 5: Clear packages lock
if [[ -f "$PROJECT_PATH/Packages/packages-lock.json" ]]; then
    rm "$PROJECT_PATH/Packages/packages-lock.json"
    print_success "✓ Cleared packages lock"
fi

# Step 6: Add EDM back with correct version
print_status "Re-adding EDM version 1.2.186..."

# Read manifest, add EDM after com.google.ads.mobile line
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' '/"com.google.ads.mobile"/a\
    "com.google.external-dependency-manager": "1.2.186",
' "$PROJECT_PATH/Packages/manifest.json"
else
    sed -i '/"com.google.ads.mobile"/a\    "com.google.external-dependency-manager": "1.2.186",' "$PROJECT_PATH/Packages/manifest.json"
fi

print_success "✓ EDM 1.2.186 added back to manifest"

# Step 7: Summary
echo
print_success "=== EDM Cleanup Complete ==="
print_status "Next steps:"
echo "1. Open Unity"
echo "2. Wait for package resolution to complete"
echo "3. Check Console for any errors"
echo "4. Test iOS Resolver: Assets > External Dependency Manager > iOS Resolver > Settings"
echo
print_warning "If the error persists, try updating to EDM 1.2.183 (known stable version)"
print_status "Backup saved: Packages/manifest.json.backup"

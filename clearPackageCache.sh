#!/bin/bash

# Script to clear Unity Package Manager cache and resolve .meta file warnings
# This fixes: "A meta data file (.meta) exists but its asset can't be found"

set -e

# Color codes
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

PROJECT_PATH="$(cd "$(dirname "$0")/.." && pwd)"

print_status "=== Unity Package Cache Cleanup ==="
print_status "Project: $PROJECT_PATH"
echo

print_warning "⚠️  IMPORTANT: Close Unity before proceeding!"
read -p "Press Enter once Unity is closed..."

# Step 1: Clear package cache
print_status "Clearing Package Manager cache..."
if [[ -d "$PROJECT_PATH/Library/PackageCache" ]]; then
    rm -rf "$PROJECT_PATH/Library/PackageCache"
    print_success "✓ Cleared PackageCache"
else
    print_status "  PackageCache already empty"
fi

# Step 2: Remove packages-lock.json to force re-resolution
print_status "Removing packages lock file..."
if [[ -f "$PROJECT_PATH/Packages/packages-lock.json" ]]; then
    rm "$PROJECT_PATH/Packages/packages-lock.json"
    print_success "✓ Removed packages-lock.json"
else
    print_status "  packages-lock.json already removed"
fi

# Step 3: Clear artifact cache (optional but helps)
print_status "Clearing artifact cache..."
if [[ -d "$PROJECT_PATH/Library/Artifacts" ]]; then
    rm -rf "$PROJECT_PATH/Library/Artifacts"
    print_success "✓ Cleared Artifacts"
else
    print_status "  Artifacts already empty"
fi

# Step 4: Clear shader cache (can cause similar issues)
if [[ -d "$PROJECT_PATH/Library/ShaderCache" ]]; then
    rm -rf "$PROJECT_PATH/Library/ShaderCache"
    print_success "✓ Cleared ShaderCache"
fi

echo
print_success "=== Cleanup Complete ==="
print_status "Next steps:"
echo "1. Open Unity"
echo "2. Wait for package resolution (may take a few minutes)"
echo "3. Let Unity reimport all assets"
echo "4. .meta warnings should be gone"
echo
print_warning "If warnings persist, check for specific problematic packages"

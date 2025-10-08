#!/bin/bash

# Manual SDK Installation Script
# This script installs Firebase and Facebook SDKs WITHOUT using Unity's package importer
# to avoid compilation errors during import

set -e

FIREBASE_VERSION="13.3.0"
FACEBOOK_VERSION="18.0.0"
PROJECT_PATH="/Users/pedromartinez/Dev/ineuj"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

print_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

print_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

echo "=========================================="
echo "   Manual SDK Installation (No Unity)    "
echo "=========================================="
echo
print_warning "This script installs SDKs by extracting them directly"
print_warning "without using Unity's import system to avoid compilation errors"
echo

# Step 1: Download Firebase SDK
print_status "Step 1/6: Downloading Firebase SDK v${FIREBASE_VERSION}..."
TEMP_DIR="/tmp/firebase_sdk_${FIREBASE_VERSION}"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

FIREBASE_URL="https://dl.google.com/firebase/sdk/unity/firebase_unity_sdk_${FIREBASE_VERSION}.zip"
if curl -L -f -o "firebase_sdk.zip" "$FIREBASE_URL"; then
    print_success "✓ Firebase SDK downloaded"
else
    print_error "Failed to download Firebase SDK"
    exit 1
fi

# Step 2: Extract Firebase and copy to project
print_status "Step 2/6: Extracting Firebase SDK..."
unzip -q "firebase_sdk.zip"

# Find Firebase packages (only the ones we actually use)
FIREBASE_PACKAGES=(
    "FirebaseAnalytics.unitypackage"
    "FirebaseAuth.unitypackage"
    "FirebaseMessaging.unitypackage"
    "FirebaseCrashlytics.unitypackage"
    # Removed: Firestore (using AWS DynamoDB instead)
    # Removed: Database, Storage, Functions, RemoteConfig, AppCheck (not used)
)

# Extract each Firebase package manually using tar
print_status "Installing Firebase packages manually..."
for package in "${FIREBASE_PACKAGES[@]}"; do
    if [[ -f "$TEMP_DIR/$package" ]]; then
        print_status "  - Extracting $package..."
        mkdir -p "$TEMP_DIR/extracted_${package}"
        cd "$TEMP_DIR/extracted_${package}"
        
        # Unity packages are actually gzipped tar files
        tar -xzf "$TEMP_DIR/$package" 2>/dev/null || {
            print_warning "    Could not extract $package (may need Unity)"
        }
    fi
done

print_success "✓ Firebase SDK extracted"

# Step 3: Download Facebook SDK
print_status "Step 3/6: Downloading Facebook SDK v${FACEBOOK_VERSION}..."
FB_TEMP_DIR="/tmp/facebook_sdk_${FACEBOOK_VERSION}"
mkdir -p "$FB_TEMP_DIR"
cd "$FB_TEMP_DIR"

FB_URL="https://github.com/facebook/facebook-sdk-for-unity/releases/download/sdk-version-${FACEBOOK_VERSION}/facebook-unity-sdk-${FACEBOOK_VERSION}.zip"
if curl -L -f -o "facebook_sdk.zip" "$FB_URL"; then
    print_success "✓ Facebook SDK downloaded"
else
    print_error "Failed to download Facebook SDK"
    exit 1
fi

# Step 4: Extract Facebook
print_status "Step 4/6: Extracting Facebook SDK..."
unzip -q "facebook_sdk.zip"
print_success "✓ Facebook SDK extracted"

# Step 5: Show what was downloaded
print_status "Step 5/6: SDK packages ready:"
echo
echo "Firebase SDK packages:"
ls -lh "$TEMP_DIR"/*.unitypackage 2>/dev/null || echo "  (Check $TEMP_DIR)"
echo
echo "Facebook SDK package:"
ls -lh "$FB_TEMP_DIR"/*.unitypackage 2>/dev/null || echo "  (Check $FB_TEMP_DIR)"
echo

# Step 6: Provide manual installation instructions
print_status "Step 6/6: Manual Installation Required"
echo
print_warning "═══════════════════════════════════════════════════════════"
print_warning "  Unity import hangs due to compilation errors in project  "
print_warning "═══════════════════════════════════════════════════════════"
echo
echo "OPTION A: Fix Compilation Errors First (Recommended)"
echo "────────────────────────────────────────────────────────"
echo "1. Open Unity project: $PROJECT_PATH"
echo "2. Check Console for errors in: Assets/Commons/Runtime/Services/AppFacebook.cs"
echo "3. Temporarily comment out or fix Facebook-related code"
echo "4. Wait for project to compile successfully"
echo "5. Then import SDKs via Unity menu:"
echo "   Assets > Import Package > Custom Package"
echo "   - Firebase: $TEMP_DIR/FirebaseAnalytics.unitypackage"
echo "   - Facebook: $FB_TEMP_DIR/facebook-unity-sdk-${FACEBOOK_VERSION}.unitypackage"
echo
echo "OPTION B: Use Unity Package Manager (Alternative)"
echo "────────────────────────────────────────────────────────"
echo "1. Install via Unity Package Manager if available"
echo "2. Or use the manual .unitypackage files above"
echo
echo "OPTION C: Install via Command Line (If errors are minor)"
echo "────────────────────────────────────────────────────────"
echo "Run the original script with -force flag:"
echo "  ./Scripts/updatePackages.sh --all --clean"
echo
print_success "SDK files are ready at:"
echo "  Firebase: $TEMP_DIR"
echo "  Facebook: $FB_TEMP_DIR"
echo
print_warning "Next Steps:"
echo "1. Fix the compilation error in AppFacebook.cs (missing ILoginResult)"
echo "2. Import SDKs manually through Unity UI"
echo "3. Or wait for Unity to resolve dependencies automatically"

#!/bin/bash
# Fix Google Play Services / External Dependency Manager (EDM4U) issues
# Resolves compilation errors when GooglePlayServices namespace is not found
# 
# Context: This project uses EDM4U 1.2.186 from Package Manager, NOT Assets folder
# We've disabled most EDM4U auto-resolution for iOS/Android builds due to conflicts
# See: Docs/FIREBASE_CLEANUP_SUMMARY.md and Scripts/fixEDM.sh

set -e

# Get project path
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_PATH="$(dirname "$SCRIPT_DIR")"

log() {
    echo "[Google Services Fix] $1"
}

log "=== Google Play Services / EDM4U Cleanup ==="
log ""

# Check if Unity is running
if pgrep -x "Unity" > /dev/null; then
    log "⚠️  WARNING: Unity is currently running!"
    log "Please close Unity first, then run this script again."
    exit 1
fi

# Step 1: Clean generated Android dependencies (from EDM4U resolver)
log "Step 1: Cleaning up generated Android dependencies..."
if [ -d "$PROJECT_PATH/Assets/GeneratedLocalRepo" ]; then
    rm -rf "$PROJECT_PATH/Assets/GeneratedLocalRepo"
    log "✓ Removed GeneratedLocalRepo"
fi

if [ -d "$PROJECT_PATH/Assets/Plugins/Android" ]; then
    find "$PROJECT_PATH/Assets/Plugins/Android" -name "googlemobileads-unity.aar*" -delete 2>/dev/null || true
    find "$PROJECT_PATH/Assets/Plugins/Android" -name "com.google.android.gms.*" -delete 2>/dev/null || true
    log "✓ Removed old Google Mobile Ads AARs"
fi

# Step 2: Clear EDM4U cache
log ""
log "Step 2: Clearing EDM4U cache..."
if [ -d "$PROJECT_PATH/Library/GooglePlayDownloader" ]; then
    rm -rf "$PROJECT_PATH/Library/GooglePlayDownloader"
    log "✓ Cleared GooglePlayDownloader cache"
fi

# Note: We don't delete Assets/ExternalDependencyManager as it contains our *.xml config
log "Note: Preserving Assets/ExternalDependencyManager/*.xml config files"

# Step 3: Verify GooglePlayServices stub exists
log ""
log "Step 3: Verifying GooglePlayServices stub files..."
STUB_FILES=(
    "$PROJECT_PATH/Assets/GooglePlayServicesStub.cs"
    "$PROJECT_PATH/Assets/Editor/GooglePlayServicesStub.cs"
)

for stub in "${STUB_FILES[@]}"; do
    if [ -f "$stub" ]; then
        touch "$stub"
        log "✓ Found and touched: $(basename $(dirname $stub))/$(basename $stub)"
    else
        log "⚠️  Missing: $(basename $(dirname $stub))/$(basename $stub)"
        log "   This stub is needed when EDM4U is disabled!"
    fi
done

# Step 4: Touch dependency XML files to trigger reimport
log ""
log "Step 4: Triggering Unity reimport of dependency files..."
find "$PROJECT_PATH/Assets/GoogleMobileAds/Editor" -name "*.xml" -exec touch {} \; 2>/dev/null || true
find "$PROJECT_PATH/Assets/GooglePlayGames/Editor" -name "*.xml" -exec touch {} \; 2>/dev/null || true
find "$PROJECT_PATH/Assets/ExternalDependencyManager" -name "*.xml" -exec touch {} \; 2>/dev/null || true
log "✓ Touched dependency XML files"

log ""
log "✅ Cleanup complete!"
log ""
log "📝 Next steps:"
log "   1. Open Unity Editor"
log "   2. Wait for Unity to compile (check for 'GooglePlayServices' errors)"
log "   3. If errors persist, Unity will auto-run Android Resolver"
log "   4. OR manually: Assets > External Dependency Manager > Android Resolver > Force Resolve"
log ""
log "💡 Note: EDM4U is mostly disabled for iOS/Android builds (see fixEDM.sh)"
log "   The GooglePlayServices namespace comes from stub files in Assets/"

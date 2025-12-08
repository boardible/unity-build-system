#!/bin/bash
#
# Apply ineuj project settings to tictac
# This script syncs critical configuration from ineuj to tictac
# while preserving tictac-specific values (bundle IDs, app names, etc.)
#

set -e

INEUJ_DIR="/Users/pedromartinez/Dev/ineuj"
TICTAC_DIR="/Users/pedromartinez/Dev/tictac"

echo "========================================"
echo "Applying ineuj settings to tictac"
echo "========================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================
# 1. PROJECT SETTINGS (selective copy)
# ============================================
echo ""
log_info "1. Updating ProjectSettings.asset (selective values)..."

PROJ_SETTINGS="$TICTAC_DIR/ProjectSettings/ProjectSettings.asset"

# Backup
cp "$PROJ_SETTINGS" "$PROJ_SETTINGS.backup"

# Apply specific settings using sed (preserving tictac-specific values)

# iOS Target Version: 16.0 (same as ineuj)
sed -i '' 's/iOSTargetOSVersionString: 15\.0/iOSTargetOSVersionString: 16.0/' "$PROJ_SETTINGS"
log_info "  - iOS Target: 16.0"

# Android Target SDK: 34 (same as ineuj)
sed -i '' 's/AndroidTargetSdkVersion: 35/AndroidTargetSdkVersion: 34/' "$PROJ_SETTINGS"
log_info "  - Android Target SDK: 34"

# Disable Unity Splash Screen (Pro feature)
sed -i '' 's/m_ShowUnitySplashScreen: 1/m_ShowUnitySplashScreen: 0/' "$PROJ_SETTINGS"
log_info "  - Unity Splash: disabled"

# iOS Stripping Level: 3 (High) - same as ineuj
sed -i '' 's/iPhoneStrippingLevel: 0/iPhoneStrippingLevel: 3/' "$PROJ_SETTINGS"
log_info "  - iOS Stripping: High (3)"

# Android display options for better compatibility
sed -i '' 's/androidResizeableActivity: 1/androidResizeableActivity: 0/' "$PROJ_SETTINGS"
log_info "  - Android Resizable Activity: disabled"

# Disable frame timing stats (performance)
sed -i '' 's/enableFrameTimingStats: 1/enableFrameTimingStats: 0/' "$PROJ_SETTINGS"
log_info "  - Frame Timing Stats: disabled"

# Android max aspect ratio: 2.1 (ineuj value)
sed -i '' 's/androidMaxAspectRatio: 2\.4/androidMaxAspectRatio: 2.1/' "$PROJ_SETTINGS"
log_info "  - Android Max Aspect: 2.1"

# Default screen size (for editor)
sed -i '' 's/defaultScreenWidth: 1920/defaultScreenWidth: 1024/' "$PROJ_SETTINGS"
sed -i '' 's/defaultScreenHeight: 1080/defaultScreenHeight: 768/' "$PROJ_SETTINGS"
log_info "  - Default Screen: 1024x768"

# Fullscreen mode: 2 (Fullscreen Window)
sed -i '' 's/fullscreenMode: 1/fullscreenMode: 2/' "$PROJ_SETTINGS"
log_info "  - Fullscreen Mode: 2"

echo ""
log_info "ProjectSettings.asset updated. Backup at $PROJ_SETTINGS.backup"

# ============================================
# 2. PACKAGES MANIFEST
# ============================================
echo ""
log_info "2. Updating Packages/manifest.json..."

MANIFEST="$TICTAC_DIR/Packages/manifest.json"
cp "$MANIFEST" "$MANIFEST.backup"

# Update apple-signin-unity to specific commit (like ineuj)
sed -i '' 's|apple-signin-unity.git#release/1.5.0|apple-signin-unity.git#0e5c49c18e8a039915f063b8e46b829421132a85|' "$MANIFEST"
log_info "  - apple-signin-unity: pinned to commit"

# Update Unity Purchasing to 5.0.3 (ineuj version)
sed -i '' 's/"com.unity.purchasing": "5.0.4"/"com.unity.purchasing": "5.0.3"/' "$MANIFEST"
log_info "  - Unity Purchasing: 5.0.3"

# Move scopedRegistries to top (like ineuj)
# This is complex, skipping for now - manual fix may be needed

echo ""
log_info "Packages/manifest.json updated. Backup at $MANIFEST.backup"

# ============================================
# 3. LINK.XML - Add missing preservations
# ============================================
echo ""
log_info "3. Checking link.xml for missing types..."

LINK_XML="$TICTAC_DIR/Assets/link.xml"

# Check if critical types are preserved
if ! grep -q "BaseItem" "$LINK_XML"; then
    log_warn "  - Missing BaseItem preservation in link.xml"
fi
if ! grep -q "StoreItem" "$LINK_XML"; then
    log_warn "  - Missing StoreItem preservation in link.xml"
fi
if ! grep -q "LocalizedData" "$LINK_XML"; then
    log_warn "  - Missing LocalizedData preservation in link.xml"
fi
if ! grep -q "LocalizationStore" "$LINK_XML"; then
    log_warn "  - Missing LocalizationStore preservation in link.xml"
fi

# Add missing types to Boardible.Commons section
# We'll do this with a Python script for accuracy
python3 << 'PYEOF'
import re

link_xml_path = "/Users/pedromartinez/Dev/tictac/Assets/link.xml"

with open(link_xml_path, 'r') as f:
    content = f.read()

# Types to add to Boardible.Commons if missing
commons_types = [
    "BaseItem",
    "StoreItem", 
    "LocalizedData",
    "LocalizationStore",
]

# Types to add to Tictac assembly if missing
tictac_types = [
    "User",
    "Profile",
    "Wallet",
    "AppConfig",
]

modified = False

# Find Boardible.Commons section and add missing types
commons_pattern = r'(<assembly fullname="Boardible\.Commons">.*?)(</assembly>)'
commons_match = re.search(commons_pattern, content, re.DOTALL)

if commons_match:
    commons_section = commons_match.group(1)
    for type_name in commons_types:
        if f'fullname="{type_name}"' not in commons_section:
            # Add before </assembly>
            new_line = f'        <type fullname="{type_name}" preserve="all"/>\n'
            insert_pos = commons_match.end(1)
            content = content[:insert_pos] + new_line + content[insert_pos:]
            print(f"  - Added {type_name} to Boardible.Commons")
            modified = True

# Find Tictac section and add missing types
tictac_pattern = r'(<assembly fullname="Tictac">.*?)(</assembly>)'
tictac_match = re.search(tictac_pattern, content, re.DOTALL)

if tictac_match:
    tictac_section = tictac_match.group(1)
    for type_name in tictac_types:
        if f'fullname="{type_name}"' not in tictac_section:
            new_line = f'        <type fullname="{type_name}" preserve="all"/>\n'
            insert_pos = tictac_match.end(1)
            content = content[:insert_pos] + new_line + content[insert_pos:]
            print(f"  - Added {type_name} to Tictac")
            modified = True

if modified:
    with open(link_xml_path, 'w') as f:
        f.write(content)
    print("  link.xml updated")
else:
    print("  link.xml already up to date")
PYEOF

# ============================================
# 4. QUALITY SETTINGS
# ============================================
echo ""
log_info "4. Syncing QualitySettings.asset..."

# Copy quality settings (these are generally safe to sync)
cp "$INEUJ_DIR/ProjectSettings/QualitySettings.asset" "$TICTAC_DIR/ProjectSettings/QualitySettings.asset"
log_info "  - QualitySettings.asset copied"

# ============================================
# 5. GRAPHICS SETTINGS
# ============================================
echo ""
log_info "5. Syncing GraphicsSettings.asset..."

cp "$INEUJ_DIR/ProjectSettings/GraphicsSettings.asset" "$TICTAC_DIR/ProjectSettings/GraphicsSettings.asset"
log_info "  - GraphicsSettings.asset copied"

# ============================================
# 6. AUDIO SETTINGS
# ============================================
echo ""
log_info "6. Syncing AudioManager.asset..."

cp "$INEUJ_DIR/ProjectSettings/AudioManager.asset" "$TICTAC_DIR/ProjectSettings/AudioManager.asset"
log_info "  - AudioManager.asset copied"

# ============================================
# 7. MEMORY SETTINGS
# ============================================
echo ""
log_info "7. Syncing MemorySettings.asset..."

cp "$INEUJ_DIR/ProjectSettings/MemorySettings.asset" "$TICTAC_DIR/ProjectSettings/MemorySettings.asset"
log_info "  - MemorySettings.asset copied"

# ============================================
# 8. CHECK FOR MISSING PACKAGES
# ============================================
echo ""
log_info "8. Checking for missing packages..."

# Packages that ineuj has but tictac might be missing
INEUJ_MANIFEST="$INEUJ_DIR/Packages/manifest.json"
TICTAC_MANIFEST="$TICTAC_DIR/Packages/manifest.json"

# Check for memory profiler
if grep -q "com.unity.memoryprofiler" "$INEUJ_MANIFEST" && ! grep -q "com.unity.memoryprofiler" "$TICTAC_MANIFEST"; then
    log_warn "  - Missing: com.unity.memoryprofiler"
fi

# Check for mobile notifications
if grep -q "com.unity.mobile.notifications" "$INEUJ_MANIFEST" && ! grep -q "com.unity.mobile.notifications" "$TICTAC_MANIFEST"; then
    log_warn "  - Missing: com.unity.mobile.notifications (may be included via features)"
fi

# Check for native share
if grep -q "yasirkula/UnityNativeShare" "$INEUJ_MANIFEST" && ! grep -q "yasirkula/UnityNativeShare" "$TICTAC_MANIFEST"; then
    log_warn "  - Missing: UnityNativeShare"
fi

# Check for device simulator
if grep -q "com.unity.device-simulator.devices" "$INEUJ_MANIFEST" && ! grep -q "com.unity.device-simulator.devices" "$TICTAC_MANIFEST"; then
    log_warn "  - Missing: com.unity.device-simulator.devices"
fi

# ============================================
# 9. SUMMARY
# ============================================
echo ""
echo "========================================"
log_info "Settings sync complete!"
echo "========================================"
echo ""
echo "Changes applied:"
echo "  ✓ ProjectSettings.asset - iOS/Android targets, stripping, etc."
echo "  ✓ Packages/manifest.json - Unity IAP version, apple-signin pin"
echo "  ✓ link.xml - Added missing type preservations"
echo "  ✓ QualitySettings.asset - Copied from ineuj"
echo "  ✓ GraphicsSettings.asset - Copied from ineuj"
echo "  ✓ AudioManager.asset - Copied from ineuj"
echo "  ✓ MemorySettings.asset - Copied from ineuj"
echo ""
echo "Backups created with .backup extension"
echo ""
log_warn "IMPORTANT: Open Unity and let it reimport. Check for any errors."
echo ""

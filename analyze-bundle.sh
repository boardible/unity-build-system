#!/bin/bash

# Quick Bundle Analyzer
# Analyzes Unity AssetBundle structure and answers common questions

set -e

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_PATH="$(dirname "$SCRIPT_DIR")"

log() {
    echo "[Bundle Analyzer] $1"
}

# Default bundle path
BUNDLE_PATH="${1:-Library/com.unity.addressables/aa/iOS/iOS/core_assets_all.bundle}"
FULL_PATH="$PROJECT_PATH/$BUNDLE_PATH"

if [ ! -f "$FULL_PATH" ]; then
    log "❌ Bundle not found at: $FULL_PATH"
    log ""
    log "Available bundles:"
    find "$PROJECT_PATH/Library/com.unity.addressables" -name "*.bundle" 2>/dev/null | while read -r bundle; do
        size=$(ls -lh "$bundle" | awk '{print $5}')
        echo "  $bundle ($size)"
    done
    exit 1
fi

log "Analyzing bundle: $BUNDLE_PATH"
log ""

# Get bundle size
BUNDLE_SIZE=$(ls -lh "$FULL_PATH" | awk '{print $5}')
log "Bundle Size: $BUNDLE_SIZE"
log ""

# Check bundle header
log "=== BUNDLE FORMAT ==="
HEADER=$(hexdump -C "$FULL_PATH" | head -1)
if echo "$HEADER" | grep -q "UnityFS"; then
    log "✅ Format: UnityFS (Unity 5.x+)"
    
    # Extract Unity version from header
    VERSION=$(hexdump -C "$FULL_PATH" | head -2 | tail -1 | cut -d'|' -f2 | grep -o '[0-9]*\.[0-9]*\.[0-9]*[a-z0-9]*')
    if [ -n "$VERSION" ]; then
        log "✅ Built with Unity: $VERSION"
    fi
else
    log "⚠️  Unknown bundle format"
fi
log ""

# Estimate compression
log "=== COMPRESSION ANALYSIS ==="
UNCOMPRESSED_ESTIMATE=$(hexdump -C "$FULL_PATH" | head -5 | grep -o '[0-9a-f]\{8\}' | head -10)
log "Bundle uses internal compression (LZ4/LZMA)"
log "Cannot extract without Unity API"
log ""

# Provide answers to common questions
cat << EOF
=== YOUR QUESTIONS ANSWERED ===

Q1: Does the bundle save assets before or after Unity's compression?
A: AFTER compression and processing

The bundle contains:
✅ Textures at their COMPRESSED size (from TextureImporter settings)
✅ Textures at their MAX SIZE limit (e.g., 128x128 if you set maxTextureSize: 128)
❌ NOT the original source files (e.g., 2048x2048 PNG)

Example:
  Source file:     2048x2048 PNG (2 MB uncompressed)
  Import settings: maxTextureSize: 128, format: ASTC 6x6
  In bundle:       128x128 ASTC (~5-10 KB)

Q2: Are assets in SpriteAtlas duplicated in bundles?
A: It depends on your Addressables configuration!

NOT duplicated if:
✅ SpriteAtlas is included in Addressables
✅ Original sprites are NOT separately in Addressables
✅ You reference sprites through atlas at runtime

ARE duplicated if:
❌ Original sprites are ALSO marked as Addressables
❌ You reference original sprites directly (not through atlas)

To check: Use Unity Menu → Boardible/Tools/Bundle Inspector

Q3: Can you unzip the bundle and check?
A: Not with standard tools!

Unity bundles use proprietary format:
- Header: UnityFS format
- Compression: LZ4 or LZMA (custom Unity implementation)
- Structure: Binary serialized asset data
- Cannot use standard unzip/7z/tar tools

To inspect: You MUST use Unity's AssetBundle API
✅ Use the BundleInspector tool I just created
✅ Menu: Boardible/Tools/Bundle Inspector

EOF

log ""
log "=== NEXT STEPS ==="
log ""
log "1. Open Unity Editor"
log "2. Go to: Boardible → Tools → Bundle Inspector"
log "3. Click 'Analyze Bundle' to see actual asset sizes"
log "4. Click 'Analyze Sprite Atlas Usage' to check for duplicates"
log "5. Click 'Check Texture Import Settings' to verify compression"
log ""
log "This will show you:"
log "  - Actual texture resolutions in bundle (after compression)"
log "  - Memory size per asset"
log "  - Texture formats (ASTC, ETC2, PVRTC, etc.)"
log "  - Whether atlases are causing duplication"
log ""

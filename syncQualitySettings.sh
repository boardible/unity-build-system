#!/bin/bash
# syncQualitySettings.sh - Sync QualitySettings across all Boardible projects
# This script updates QualitySettings.asset to use consistent graphics settings
#
# Usage: ./syncQualitySettings.sh [project_path]
# If no project path provided, syncs the current project

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values for quality settings (matching ineuj reference)
VSYNC_COUNT=0
SHADOWS_DISABLED=0

# Function to patch QualitySettings.asset
patch_quality_settings() {
    local project_path="$1"
    local quality_file="$project_path/ProjectSettings/QualitySettings.asset"
    
    if [ ! -f "$quality_file" ]; then
        echo "ERROR: QualitySettings.asset not found at $quality_file"
        return 1
    fi
    
    echo "Patching QualitySettings at: $quality_file"
    
    # Create backup
    cp "$quality_file" "$quality_file.backup"
    
    # Patch vSyncCount from 1 to 0 (better for 120Hz displays, saves battery)
    sed -i '' 's/vSyncCount: 1/vSyncCount: 0/g' "$quality_file"
    
    # Patch shadows from enabled to disabled for mobile 2D games
    # shadows: 0 = Disable, 1 = Hard Only, 2 = All
    sed -i '' 's/shadows: 2/shadows: 0/g' "$quality_file"
    sed -i '' 's/shadows: 1/shadows: 0/g' "$quality_file"
    
    # Patch asyncUploadTimeSlice for smoother loading (reduce from 10 to 4)
    sed -i '' 's/asyncUploadTimeSlice: 10/asyncUploadTimeSlice: 4/g' "$quality_file"
    sed -i '' 's/asyncUploadTimeSlice: 8/asyncUploadTimeSlice: 4/g' "$quality_file"
    sed -i '' 's/asyncUploadTimeSlice: 6/asyncUploadTimeSlice: 4/g' "$quality_file"
    
    # Enable streaming mipmaps for better memory management
    sed -i '' 's/streamingMipmapsActive: 0/streamingMipmapsActive: 1/g' "$quality_file"
    
    echo "✓ Patched vSyncCount to 0"
    echo "✓ Patched shadows to disabled"
    echo "✓ Patched asyncUploadTimeSlice to 4"
    echo "✓ Enabled streamingMipmapsActive"
    echo "Backup saved at: $quality_file.backup"
    
    return 0
}

# Main logic
if [ -n "$1" ]; then
    # Sync specific project
    patch_quality_settings "$1"
else
    # Sync current project (detect from script location)
    # Scripts is usually at project_root/Scripts or as submodule
    PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
    
    if [ -f "$PROJECT_ROOT/ProjectSettings/QualitySettings.asset" ]; then
        patch_quality_settings "$PROJECT_ROOT"
    else
        echo "Usage: $0 <project_path>"
        echo "Example: $0 /Users/me/Dev/tictac"
        exit 1
    fi
fi

echo ""
echo "=== QualitySettings sync complete ==="
echo ""
echo "NOTE: URP Pipeline assignment must be done manually in Unity Editor:"
echo "  1. Open Edit > Project Settings > Quality"
echo "  2. For each quality level, assign the corresponding URP asset:"
echo "     - Low: URP_Low.asset"
echo "     - Medium: URP_Medium.asset"
echo "     - High: URP_High.asset"
echo "  3. URP assets should be in Assets/Settings/URP/ or similar"

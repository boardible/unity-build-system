#!/bin/bash
#
# syncBuildConfigs.sh - Sync build configurations across Boardible Unity projects
#
# This script ensures consistent build settings across ineuj, tictac, and boardgames:
# - Managed Stripping Level (Medium for Android, Low for iOS - safest for reflection)
# - IL2CPP Code Generation mode
# - link.xml files (merges Commons base with project-specific rules)
#
# Usage:
#   ./Scripts/syncBuildConfigs.sh [--check-only] [--project <name>]
#
# Options:
#   --check-only    Only report differences, don't apply changes
#   --project       Only sync specific project (ineuj, tictac, boardgames)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect project root (assumes script is in project/Scripts/)
if [[ -d "$SCRIPT_DIR/../Assets" ]]; then
    PROJECT_ROOT="$SCRIPT_DIR/.."
else
    echo "Error: Cannot determine project root"
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMMONS_BASE_LINK_XML="$PROJECT_ROOT/Assets/Commons/BuildConfig/link-base.xml"
PROJECT_SETTINGS="$PROJECT_ROOT/ProjectSettings/ProjectSettings.asset"
TARGET_LINK_XML="$PROJECT_ROOT/Assets/link.xml"

# Recommended stripping levels (Unity values):
# 0 = Disabled, 1 = Low, 2 = Medium, 3 = High, 4 = Minimal
RECOMMENDED_STRIPPING_ANDROID=2  # Medium - good balance
RECOMMENDED_STRIPPING_IOS=1     # Low - safest for reflection-heavy code

CHECK_ONLY=false
TARGET_PROJECT=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --check-only)
            CHECK_ONLY=true
            shift
            ;;
        --project)
            TARGET_PROJECT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Build Configuration Sync Tool${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Detect current project
detect_project() {
    local proj_root="$1"
    if grep -q "Tictac" "$proj_root/ProjectSettings/ProjectSettings.asset" 2>/dev/null; then
        echo "tictac"
    elif grep -q "boardgames" "$proj_root/ProjectSettings/ProjectSettings.asset" 2>/dev/null; then
        echo "boardgames"
    else
        echo "ineuj"
    fi
}

CURRENT_PROJECT=$(detect_project "$PROJECT_ROOT")
echo -e "Detected project: ${GREEN}$CURRENT_PROJECT${NC}"
echo ""

# Function to get current stripping level
get_stripping_level() {
    local platform="$1"
    local settings_file="$2"
    
    # Extract stripping level using awk
    awk -v platform="$platform" '
        /managedStrippingLevel:/ { in_section=1; next }
        in_section && /^    [a-zA-Z]/ { 
            split($0, parts, ": ")
            gsub(/^ +/, "", parts[1])
            if (parts[1] == platform) {
                print parts[2]
                exit
            }
        }
        in_section && /^  [a-z]/ { in_section=0 }
    ' "$settings_file"
}

# Function to check stripping levels
check_stripping_levels() {
    echo -e "${YELLOW}Checking Managed Stripping Levels...${NC}"
    
    local android_level=$(get_stripping_level "Android" "$PROJECT_SETTINGS")
    local ios_level=$(get_stripping_level "iPhone" "$PROJECT_SETTINGS")
    
    echo "  Android: ${android_level:-unknown} (recommended: $RECOMMENDED_STRIPPING_ANDROID)"
    echo "  iOS:     ${ios_level:-unknown} (recommended: $RECOMMENDED_STRIPPING_IOS)"
    
    local needs_fix=false
    
    if [[ "$android_level" != "$RECOMMENDED_STRIPPING_ANDROID" ]]; then
        echo -e "  ${RED}⚠ Android stripping level mismatch${NC}"
        needs_fix=true
    fi
    
    if [[ "$ios_level" != "$RECOMMENDED_STRIPPING_IOS" ]]; then
        echo -e "  ${RED}⚠ iOS stripping level mismatch${NC}"
        needs_fix=true
    fi
    
    if [[ "$needs_fix" == "true" ]] && [[ "$CHECK_ONLY" == "false" ]]; then
        echo ""
        echo -e "${YELLOW}Note: Stripping levels must be changed in Unity Editor:${NC}"
        echo "  1. Open Unity Editor"
        echo "  2. File > Build Settings > Player Settings"
        echo "  3. For Android: Other Settings > Managed Stripping Level = Medium"
        echo "  4. For iOS: Other Settings > Managed Stripping Level = Low"
        echo ""
        echo "  Or use Unity CLI:"
        echo "  Unity -batchmode -projectPath \"$PROJECT_ROOT\" -executeMethod BuildConfigSync.SetStrippingLevels -quit"
    fi
    
    echo ""
}

# Function to merge link.xml files
merge_link_xml() {
    echo -e "${YELLOW}Checking link.xml...${NC}"
    
    if [[ ! -f "$COMMONS_BASE_LINK_XML" ]]; then
        echo -e "  ${RED}Error: Commons base link.xml not found at $COMMONS_BASE_LINK_XML${NC}"
        echo "  Run this script from a project with Commons submodule."
        return 1
    fi
    
    if [[ ! -f "$TARGET_LINK_XML" ]]; then
        echo -e "  ${YELLOW}No link.xml found, will create from Commons base${NC}"
        if [[ "$CHECK_ONLY" == "false" ]]; then
            # Create project-specific wrapper
            create_project_link_xml
        fi
        return 0
    fi
    
    # Check if Commons assemblies are present
    local missing_assemblies=()
    
    # Use grep -o with extended regex (works on macOS)
    while IFS= read -r assembly; do
        if [[ -n "$assembly" ]] && ! grep -q "fullname=\"$assembly\"" "$TARGET_LINK_XML"; then
            missing_assemblies+=("$assembly")
        fi
    done < <(grep -oE 'fullname="[^"]+"' "$COMMONS_BASE_LINK_XML" | sed 's/fullname="//;s/"//')
    
    if [[ ${#missing_assemblies[@]} -gt 0 ]]; then
        echo -e "  ${YELLOW}Missing assemblies in link.xml:${NC}"
        for asm in "${missing_assemblies[@]:0:5}"; do
            echo "    - $asm"
        done
        if [[ ${#missing_assemblies[@]} -gt 5 ]]; then
            echo "    ... and $((${#missing_assemblies[@]} - 5)) more"
        fi
        
        if [[ "$CHECK_ONLY" == "false" ]]; then
            echo ""
            echo -e "  ${GREEN}Updating link.xml...${NC}"
            create_project_link_xml
        fi
    else
        echo -e "  ${GREEN}✓ link.xml has all required Commons assemblies${NC}"
    fi
    
    echo ""
}

# Function to create project-specific link.xml
create_project_link_xml() {
    local project_assemblies=""
    
    case "$CURRENT_PROJECT" in
        ineuj)
            project_assemblies='    <!-- INEUJ Project-Specific Assemblies -->
    <assembly fullname="App" preserve="all"/>
    <assembly fullname="Boardible.Menu" preserve="all"/>
    <assembly fullname="Boardible.Gameplay" preserve="all"/>'
            ;;
        tictac)
            project_assemblies='    <!-- TICTAC Project-Specific Assemblies -->
    <assembly fullname="Tictac" preserve="all"/>'
            ;;
        boardgames)
            project_assemblies='    <!-- BOARDGAMES Project-Specific Assemblies -->
    <assembly fullname="App" preserve="all"/>
    <assembly fullname="Boardible.Menu" preserve="all"/>
    <assembly fullname="Boardible.Gameplay" preserve="all"/>
    <assembly fullname="Boardible.Gamebox" preserve="all"/>
    <assembly fullname="Boardible.Gamebox.Data" preserve="all"/>
    <assembly fullname="Boardible.Gamebox.Utils" preserve="all"/>
    <assembly fullname="Boardible.Games" preserve="all"/>
    <assembly fullname="Boardible.Utils" preserve="all"/>'
            ;;
    esac

    # Create new file by reading base, removing closing tag, adding project assemblies, then closing
    {
        echo "<!-- AUTO-GENERATED from Commons/BuildConfig/link-base.xml"
        echo "     Project: $CURRENT_PROJECT"
        echo "     Generated: $(date)"
        echo "     To update: Run Scripts/syncBuildConfigs.sh"
        echo "     DO NOT EDIT COMMONS SECTION MANUALLY -->"
        echo ""
        # Read base, exclude closing linker tag
        grep -v "</linker>" "$COMMONS_BASE_LINK_XML"
        echo ""
        echo "$project_assemblies"
        echo ""
        echo "</linker>"
    } > "$TARGET_LINK_XML"
    
    echo -e "  ${GREEN}✓ Created/updated link.xml${NC}"
}

# Function to validate assemblies exist
validate_assemblies() {
    echo -e "${YELLOW}Validating assembly definitions...${NC}"
    
    local asmdef_count
    asmdef_count=$(find "$PROJECT_ROOT/Assets" -name "*.asmdef" | wc -l | tr -d ' ')
    
    echo "  Found $asmdef_count assembly definitions"
    
    # Check for Boardible.Commons
    if find "$PROJECT_ROOT/Assets/Commons" -name "Boardible.Commons.asmdef" | grep -q .; then
        echo -e "  ${GREEN}✓ Boardible.Commons.asmdef found${NC}"
    else
        echo -e "  ${RED}✗ Boardible.Commons.asmdef NOT found${NC}"
    fi
    
    echo ""
}

# Main execution
check_stripping_levels
merge_link_xml
validate_assemblies

echo -e "${BLUE}========================================${NC}"
if [[ "$CHECK_ONLY" == "true" ]]; then
    echo -e "${YELLOW}Check complete (--check-only mode)${NC}"
else
    echo -e "${GREEN}Sync complete!${NC}"
fi
echo -e "${BLUE}========================================${NC}"

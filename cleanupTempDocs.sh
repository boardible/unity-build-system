#!/bin/bash

# Documentation Cleanup Script
# Removes temporary analysis/debug documents that should be in git history, not workspace
# Run this after completing major features or bug fixes

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_PATH="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Documentation Cleanup - Temporary Analysis Files         ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Patterns for temporary docs that should be deleted
TEMP_PATTERNS=(
    "*_FIX_*.md"
    "*_DEBUG_*.md"
    "*_ANALYSIS*.md"
    "*_PLAN.md"
    "*_ATTEMPT_*.md"
    "*_SUMMARY*.md"
    "*_COMPLETED.md"
    "*_IMPLEMENTATION*.md"
    "*CLEANUP*.md"
    "*REFACTOR*.md"
)

# Exceptions - files we want to KEEP even if they match patterns
KEEP_FILES=(
    "ARCHITECTURE_REFERENCE.md"
    "README.md"
    "Docs/ANDROID_BUILD_OPTIMIZATION_SUMMARY.md"  # Permanent reference
    "Docs/LINK_XML_REFLECTION_ANALYSIS.md"        # Permanent reference
    "Docs/GRAPHICS_OPTIMIZATION_ANALYSIS.md"      # Permanent reference
    "Scripts/IMPLEMENTATION_SUMMARY.md"           # Build system docs
    "Scripts/README.md"
    "TESTFLIGHT_EXPORT_COMPLIANCE_FIX.md"         # Permanent guide
    "Docs/COCOAPODS_CDN_FIX.md"                   # Permanent guide
)

# Function to check if file should be kept
should_keep_file() {
    local file=$1
    local relative_path="${file#$PROJECT_PATH/}"
    
    for keep in "${KEEP_FILES[@]}"; do
        if [[ "$relative_path" == "$keep" ]] || [[ "$relative_path" == *"/$keep" ]]; then
            return 0  # Keep this file
        fi
    done
    return 1  # Delete this file
}

# Find and categorize files
TEMP_FILES=()
KEPT_FILES=()

cd "$PROJECT_PATH"

echo -e "${YELLOW}Scanning for temporary documentation files...${NC}"
echo ""

for pattern in "${TEMP_PATTERNS[@]}"; do
    while IFS= read -r -d '' file; do
        if [[ -f "$file" ]]; then
            if should_keep_file "$file"; then
                KEPT_FILES+=("$file")
            else
                TEMP_FILES+=("$file")
            fi
        fi
    done < <(find . -maxdepth 2 -type f -iname "$pattern" -print0 2>/dev/null)
done

# Display findings
if [ ${#TEMP_FILES[@]} -eq 0 ]; then
    echo -e "${GREEN}✓ No temporary documentation files found!${NC}"
    echo -e "${GREEN}  Workspace is clean.${NC}"
    echo ""
    exit 0
fi

echo -e "${YELLOW}Found ${#TEMP_FILES[@]} temporary documentation file(s):${NC}"
echo ""

for file in "${TEMP_FILES[@]}"; do
    relative_path="${file#./}"
    file_size=$(du -h "$file" | cut -f1)
    line_count=$(wc -l < "$file")
    echo -e "  ${RED}✗${NC} $relative_path"
    echo -e "    Size: $file_size, Lines: $line_count"
done

echo ""

if [ ${#KEPT_FILES[@]} -gt 0 ]; then
    echo -e "${GREEN}Keeping ${#KEPT_FILES[@]} permanent documentation file(s):${NC}"
    echo ""
    for file in "${KEPT_FILES[@]}"; do
        relative_path="${file#./}"
        echo -e "  ${GREEN}✓${NC} $relative_path (permanent reference)"
    done
    echo ""
fi

# Prompt for confirmation
echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  WARNING: This will DELETE the temporary files above!${NC}"
echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "These files contain analysis/debugging information that should be:"
echo -e "  1. Consolidated into ${GREEN}ARCHITECTURE_REFERENCE.md${NC}"
echo -e "  2. Converted to code comments"
echo -e "  3. Preserved in git history via commit messages"
echo ""
echo -e "${BLUE}Before deleting, consider:${NC}"
echo -e "  • Review files for important patterns/fixes"
echo -e "  • Update ARCHITECTURE_REFERENCE.md with key learnings"
echo -e "  • Add detailed commit message documenting the work"
echo ""

read -p "Do you want to DELETE these files? (yes/no): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${BLUE}Cleanup cancelled. No files were deleted.${NC}"
    echo ""
    exit 0
fi

# Delete files
echo -e "${BLUE}Deleting temporary documentation files...${NC}"
echo ""

DELETED_COUNT=0
for file in "${TEMP_FILES[@]}"; do
    relative_path="${file#./}"
    if rm "$file"; then
        echo -e "  ${GREEN}✓${NC} Deleted: $relative_path"
        ((DELETED_COUNT++))
    else
        echo -e "  ${RED}✗${NC} Failed to delete: $relative_path"
    fi
done

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Cleanup Complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}Deleted: $DELETED_COUNT file(s)${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Review and update ${GREEN}ARCHITECTURE_REFERENCE.md${NC} with key learnings"
echo -e "  2. Commit with descriptive message explaining what was done"
echo -e "  3. Consider if any patterns should be added to code comments"
echo ""
echo -e "${BLUE}To prevent this in the future:${NC}"
echo -e "  • Add 'cleanupTempDocs.sh' to your workflow"
echo -e "  • Run before committing major features"
echo -e "  • Copilot instructions have been updated to avoid creating these"
echo ""

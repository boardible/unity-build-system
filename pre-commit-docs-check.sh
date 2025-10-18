#!/bin/bash

# Git Pre-Commit Hook - Documentation Policy Enforcement
# Warns if trying to commit temporary documentation files
# Install: cp Scripts/pre-commit-docs-check.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# Check for temporary doc patterns in staged files
TEMP_DOCS=$(git diff --cached --name-only | grep -iE '(FIX|DEBUG|ANALYSIS|PLAN|SUMMARY|ATTEMPT|COMPLETED|IMPLEMENTATION|CLEANUP|REFACTOR).*\.md$' || true)

if [ -z "$TEMP_DOCS" ]; then
    # No temp docs found, proceed
    exit 0
fi

# Temp docs detected - warn user
echo ""
echo -e "${RED}═══════════════════════════════════════════════════════════${NC}"
echo -e "${RED}  ⚠️  TEMPORARY DOCUMENTATION DETECTED${NC}"
echo -e "${RED}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}The following temporary documentation files are staged:${NC}"
echo ""
echo "$TEMP_DOCS" | while read file; do
    echo -e "  ${RED}✗${NC} $file"
done
echo ""
echo -e "${YELLOW}Temporary docs violate the documentation policy:${NC}"
echo -e "  • These should be in ${GREEN}ARCHITECTURE_REFERENCE.md${NC}"
echo -e "  • Or in ${GREEN}code comments${NC}"
echo -e "  • Or in ${GREEN}git commit messages${NC}"
echo ""
echo -e "${GREEN}To fix:${NC}"
echo -e "  1. Run: ${GREEN}./Scripts/cleanupTempDocs.sh${NC}"
echo -e "  2. Extract key learnings into ARCHITECTURE_REFERENCE.md"
echo -e "  3. Unstage these files: ${GREEN}git reset HEAD <file>${NC}"
echo ""

read -p "Commit anyway? (yes/no): " -r
echo ""

if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${YELLOW}⚠️  Proceeding with commit (docs policy violation)${NC}"
    exit 0
else
    echo -e "${GREEN}✓ Commit cancelled. Fix documentation first.${NC}"
    exit 1
fi

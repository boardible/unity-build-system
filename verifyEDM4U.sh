#!/bin/bash

# Verification script to check if all EDM4U issues are fixed

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_section() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

ERRORS=0

print_section "EDM4U Status Check"

# Check 1: Package Manager
print_section "1. Package Manager (may exist - required by Firebase)"
if ls -d Library/PackageCache/com.google.external-dependency-manager@* 2>/dev/null; then
    print_warning "EDM4U in Package Cache (required by Firebase packages)"
    print_success "This is OK - Firebase packages depend on EDM4U"
else
    print_success "Not in Package Cache"
fi

# Check 2: Manifest
print_section "2. Packages Manifest (EDM4U may be transitive dependency)"
if grep -q "external-dependency-manager" Packages/manifest.json; then
    print_warning "EDM4U explicitly in manifest (consider removing - Firebase will restore it)"
else
    print_success "Not explicitly in manifest (will be restored by Firebase)"
fi

# Check 3: Assets folder
print_section "3. Assets Folder (should be disabled)"
if [ -f "Assets/ExternalDependencyManager/Editor/1.2.182/Google.IOSResolver.dll" ]; then
    print_error "Assets version is ENABLED!"
    ERRORS=$((ERRORS+1))
elif [ -f "Assets/ExternalDependencyManager/Editor/1.2.182/Google.IOSResolver.dll.DISABLED" ]; then
    print_success "Assets version is disabled"
else
    print_warning "Assets version DLL not found (may be OK if removed entirely)"
fi

# Check 4: Podfile sources
print_section "4. Podfile Sources (should have only one)"
if [ -f "build/iOS/Podfile" ]; then
    SOURCE_COUNT=$(grep "^source" build/iOS/Podfile | wc -l | tr -d ' ')
    if [ "$SOURCE_COUNT" -eq 1 ]; then
        print_success "Single source found:"
        grep "^source" build/iOS/Podfile
    elif [ "$SOURCE_COUNT" -gt 1 ]; then
        print_error "Multiple sources found:"
        grep "^source" build/iOS/Podfile
        ERRORS=$((ERRORS+1))
    else
        print_warning "No source found in Podfile (may be OK if never built)"
    fi
else
    print_warning "No Podfile found (will be generated on first build)"
fi

# Check 5: EDM4U settings
print_section "5. EDM4U Integration Method (should be 0)"
if [ -f "Assets/ExternalDependencyManager/Editor/IOSResolverSettings.xml" ]; then
    METHOD=$(grep "cocoapodsIntegrationMethod" Assets/ExternalDependencyManager/Editor/IOSResolverSettings.xml | sed 's/.*>\([0-9]\)<.*/\1/')
    if [ "$METHOD" = "0" ]; then
        print_success "Integration method is 0 (None)"
    else
        print_error "Integration method is $METHOD (should be 0)"
        ERRORS=$((ERRORS+1))
    fi
else
    print_warning "IOSResolverSettings.xml not found"
fi

# Summary
print_section "Summary"
if [ $ERRORS -eq 0 ]; then
    print_success "All checks passed! Ready to build."
    echo ""
    echo "Run: ./Scripts/unityBuild.sh --platform ios --profile dev"
    exit 0
else
    print_error "$ERRORS issue(s) found. Please fix before building."
    exit 1
fi

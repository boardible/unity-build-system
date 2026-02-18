#!/bin/bash

# Firebase SDK Updater Script
# Usage: ./updateFirebase.sh [version] [unity_path] [project_path]

set -e

FIREBASE_VERSION=${1:-"13.3.0"}
UNITY_PATH=${2:-"/Applications/Unity/Hub/Editor/6000.3.7f1/Unity.app/Contents/MacOS/Unity"}
PROJECT_PATH=${3:-"/Users/pedromartinez/Dev/ineuj"}

# Minimum supported Firebase version
MIN_FIREBASE_VERSION="13.0.0"
# Known deprecated versions to warn about
DEPRECATED_VERSIONS=("11.14.0" "12.0.0" "12.1.0" "12.4.1")

DOWNLOAD_URL="https://dl.google.com/firebase/sdk/unity/firebase_unity_sdk_${FIREBASE_VERSION}.zip"
TEMP_DIR="/tmp/firebase_sdk_${FIREBASE_VERSION}"

echo "=== Firebase Unity SDK Updater ==="
echo "Version: ${FIREBASE_VERSION}"
echo "Unity Path: ${UNITY_PATH}"
echo "Project Path: ${PROJECT_PATH}"
echo "Download URL: ${DOWNLOAD_URL}"
echo

# Function to compare version numbers (returns 0 if v1 >= v2, 1 otherwise)
version_ge() {
    local v1=$1
    local v2=$2
    
    # Split versions into arrays
    IFS='.' read -ra V1 <<< "$v1"
    IFS='.' read -ra V2 <<< "$v2"
    
    # Compare major, minor, patch
    for i in 0 1 2; do
        local num1=${V1[$i]:-0}
        local num2=${V2[$i]:-0}
        
        if [[ $num1 -gt $num2 ]]; then
            return 0
        elif [[ $num1 -lt $num2 ]]; then
            return 1
        fi
    done
    
    return 0
}

# Validate Firebase version
echo "Validating Firebase SDK version..."

# Check if version is deprecated
for deprecated_ver in "${DEPRECATED_VERSIONS[@]}"; do
    if [[ "$FIREBASE_VERSION" == "$deprecated_ver" ]]; then
        echo "⚠️  WARNING: Firebase SDK version ${FIREBASE_VERSION} is deprecated!"
        echo "    This version is known to have conflicts in the build system."
        echo "    Recommended: Use version ${MIN_FIREBASE_VERSION} or higher."
        echo ""
        read -p "Do you want to continue anyway? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            echo "Update cancelled."
            exit 1
        fi
    fi
done

# Check minimum version
if ! version_ge "$FIREBASE_VERSION" "$MIN_FIREBASE_VERSION"; then
    echo "❌ ERROR: Firebase SDK version ${FIREBASE_VERSION} is below minimum supported version ${MIN_FIREBASE_VERSION}"
    echo ""
    echo "   Minimum Requirements:"
    echo "   - Firebase SDK: ${MIN_FIREBASE_VERSION}+"
    echo "   - Swift: 5.9+"
    echo "   - iOS: 13.0+"
    echo ""
    echo "   Current build configuration:"
    echo "   - iOS Deployment Target: 16.0"
    echo "   - Swift Version: Auto-detected (6.2)"
    echo ""
    echo "   Using older Firebase versions can cause:"
    echo "   - CocoaPods version conflicts"
    echo "   - Swift module compatibility issues"
    echo "   - Build/archive failures"
    echo ""
    echo "Update cancelled for safety."
    exit 1
fi

echo "✓ Firebase SDK version ${FIREBASE_VERSION} validated"
echo ""

# Check if Firebase is already installed and get current version
if [[ -d "${PROJECT_PATH}/Assets/Firebase" ]]; then
    echo "Existing Firebase installation detected."
    
    # Try to find current version from Firebase version file
    VERSION_FILE="${PROJECT_PATH}/Assets/Firebase/Editor/Firebase.Editor.dll"
    if [[ -f "$VERSION_FILE" ]]; then
        # Get file modification time as a proxy for version (not perfect but helpful)
        existing_date=$(stat -f "%Sm" -t "%Y-%m-%d" "$VERSION_FILE" 2>/dev/null || echo "unknown")
        echo "Existing Firebase installation date: ${existing_date}"
    fi
    
    echo ""
    echo "⚠️  This will replace your existing Firebase SDK installation."
    echo "   Target version: ${FIREBASE_VERSION}"
    echo "   Backup location: ${PROJECT_PATH}/Backup/firebase_backup_$(date +%Y%m%d_%H%M%S)"
    echo ""
    read -p "Continue with update? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo "Update cancelled."
        exit 0
    fi
    
    # Create backup
    BACKUP_DIR="${PROJECT_PATH}/Backup/firebase_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    echo "Creating backup..."
    cp -r "${PROJECT_PATH}/Assets/Firebase" "$BACKUP_DIR/" 2>/dev/null || true
    echo "✓ Backup created at: ${BACKUP_DIR}"
    echo ""
fi

# Create temporary directory
mkdir -p "${TEMP_DIR}"
cd "${TEMP_DIR}"

# Download Firebase SDK
echo "Downloading Firebase Unity SDK v${FIREBASE_VERSION}..."
curl -L -o "firebase_unity_sdk_${FIREBASE_VERSION}.zip" "${DOWNLOAD_URL}"

# Extract SDK
echo "Extracting Firebase SDK..."
unzip -q "firebase_unity_sdk_${FIREBASE_VERSION}.zip"

# Define packages to import (Firebase SDK structure)
# Firebase 13.x uses new naming convention (lowercase with underscores)
PACKAGES=(
    "firebase_analytics.unitypackage"
    "firebase_auth.unitypackage"
    "firebase_crashlytics.unitypackage"
    "firebase_firestore.unitypackage"
    "firebase_messaging.unitypackage"
)

# Import each package from the firebase_unity_sdk subdirectory
IMPORTED_COUNT=0
SDK_SUBDIR="${TEMP_DIR}/firebase_unity_sdk"

if [[ -d "${SDK_SUBDIR}" ]]; then
    echo "Found Firebase SDK subdirectory: ${SDK_SUBDIR}"
    
    for package in "${PACKAGES[@]}"; do
        package_path="${SDK_SUBDIR}/${package}"
        if [[ -f "${package_path}" ]]; then
            echo "Importing ${package}..."
            
            # Try to import the package
            "${UNITY_PATH}" -batchmode -quit \
                -projectPath "${PROJECT_PATH}" \
                -importPackage "${package_path}" \
                -logFile /tmp/unity_firebase_import.log
            
            # Check if import was successful
            if [[ $? -eq 0 ]]; then
                echo "✓ Successfully imported ${package}"
                ((IMPORTED_COUNT++))
            else
                echo "✗ Failed to import ${package} - check /tmp/unity_firebase_import.log"
                
                # Show last few lines of error log
                echo "Last errors from Unity log:"
                tail -10 /tmp/unity_firebase_import.log | grep -E "(error|Error|ERROR)" || echo "No specific errors found in log"
                
                # Continue with other packages instead of failing completely
                echo "Continuing with remaining packages..."
            fi
        else
            echo "Warning: ${package} not found in SDK"
        fi
    done
    
    # Try new naming convention if old one didn't work
    if [[ $IMPORTED_COUNT -eq 0 ]]; then
        echo "Trying new Firebase SDK naming convention..."
        for package in "${NEW_PACKAGES[@]}"; do
            package_path="${SDK_SUBDIR}/${package}"
            if [[ -f "${package_path}" ]]; then
                echo "Importing ${package}..."
                "${UNITY_PATH}" -batchmode -quit \
                    -projectPath "${PROJECT_PATH}" \
                    -importPackage "${package_path}" \
                    -logFile /tmp/unity_firebase_import.log
                ((IMPORTED_COUNT++))
            else
                echo "Warning: ${package} not found in SDK"
            fi
        done
    fi
else
    echo "Firebase SDK subdirectory not found. Checking root directory..."
    
    for package in "${PACKAGES[@]}"; do
        package_path="${TEMP_DIR}/${package}"
        if [[ -f "${package_path}" ]]; then
            echo "Importing ${package}..."
            "${UNITY_PATH}" -batchmode -quit \
                -projectPath "${PROJECT_PATH}" \
                -importPackage "${package_path}" \
                -logFile /tmp/unity_firebase_import.log
            ((IMPORTED_COUNT++))
        else
            echo "Warning: ${package} not found in SDK"
        fi
    done
fi

# If still no packages found, list what's actually in the SDK
if [[ $IMPORTED_COUNT -eq 0 ]]; then
    echo "No packages imported. Contents of Firebase SDK:"
    ls -la "${TEMP_DIR}/"
    if [[ -d "${SDK_SUBDIR}" ]]; then
        echo "Contents of Firebase SDK subdirectory:"
        ls -la "${SDK_SUBDIR}/"
    fi
    echo "Looking for .unitypackage files:"
    find "${TEMP_DIR}" -name "*.unitypackage" -type f
fi

# Clean up
echo "Cleaning up temporary files..."
rm -rf "${TEMP_DIR}"

echo "=== Firebase SDK Update Complete ==="
echo "Check Unity console for any import errors."
#!/bin/bash

# Firebase SDK Updater Script
# Usage: ./updateFirebase.sh [version] [unity_path] [project_path]

set -e

FIREBASE_VERSION=${1:-"13.3.0"}
UNITY_PATH=${2:-"/Applications/Unity/Hub/Editor/6000.0.58f1/Unity.app/Contents/MacOS/Unity"}
PROJECT_PATH=${3:-"/Users/pedromartinez/Dev/ineuj"}

DOWNLOAD_URL="https://dl.google.com/firebase/sdk/unity/firebase_unity_sdk_${FIREBASE_VERSION}.zip"
TEMP_DIR="/tmp/firebase_sdk_${FIREBASE_VERSION}"

echo "=== Firebase Unity SDK Updater ==="
echo "Version: ${FIREBASE_VERSION}"
echo "Unity Path: ${UNITY_PATH}"
echo "Project Path: ${PROJECT_PATH}"
echo "Download URL: ${DOWNLOAD_URL}"
echo

# Create temporary directory
mkdir -p "${TEMP_DIR}"
cd "${TEMP_DIR}"

# Download Firebase SDK
echo "Downloading Firebase Unity SDK v${FIREBASE_VERSION}..."
curl -L -o "firebase_unity_sdk_${FIREBASE_VERSION}.zip" "${DOWNLOAD_URL}"

# Extract SDK
echo "Extracting Firebase SDK..."
unzip -q "firebase_unity_sdk_${FIREBASE_VERSION}.zip"

# Define packages to import (Firebase SDK structure changed in recent versions)
# Check for both old and new structures
PACKAGES=(
    "FirebaseAnalytics.unitypackage"
    "FirebaseAuth.unitypackage"
    "FirebaseCrashlytics.unitypackage"
    "FirebaseFirestore.unitypackage"
    "FirebaseFunctions.unitypackage" 
    "FirebaseMessaging.unitypackage"
    "FirebaseRemoteConfig.unitypackage"
    "FirebaseStorage.unitypackage"
)

# New Firebase SDK structure (since v12+)
NEW_PACKAGES=(
    "firebase_analytics.unitypackage"
    "firebase_auth.unitypackage"
    "firebase_crashlytics.unitypackage"
    "firebase_firestore.unitypackage"
    "firebase_functions.unitypackage"
    "firebase_messaging.unitypackage"
    "firebase_remote_config.unitypackage"
    "firebase_storage.unitypackage"
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
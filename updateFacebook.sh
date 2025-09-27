#!/bin/bash

# Facebook SDK for Unity Updater Script
# Usage: ./updateFacebook.sh [version] [unity_path] [project_path]

set -e

FACEBOOK_VERSION=${1:-"18.0.0"}
UNITY_PATH=${2:-"/Applications/Unity/Hub/Editor/6000.0.58f1/Unity.app/Contents/MacOS/Unity"}
PROJECT_PATH=${3:-"/Users/pedromartinez/Dev/ineuj"}

DOWNLOAD_URL="https://github.com/facebook/facebook-sdk-for-unity/releases/download/sdk-version-${FACEBOOK_VERSION}/facebook-unity-sdk-${FACEBOOK_VERSION}.zip"
TEMP_DIR="/tmp/facebook_sdk_${FACEBOOK_VERSION}"
BACKUP_DIR="${PROJECT_PATH}/Temp/facebook_backup_$(date +%Y%m%d_%H%M%S)"

echo "=== Facebook Unity SDK Updater ==="
echo "Version: ${FACEBOOK_VERSION}"
echo "Unity Path: ${UNITY_PATH}"
echo "Project Path: ${PROJECT_PATH}"
echo "Download URL: ${DOWNLOAD_URL}"
echo

# Create temporary and backup directories
mkdir -p "${TEMP_DIR}"
mkdir -p "${BACKUP_DIR}"

# Backup current Facebook SDK
echo "Backing up current Facebook SDK..."
if [[ -d "${PROJECT_PATH}/Assets/FacebookSDK" ]]; then
    cp -r "${PROJECT_PATH}/Assets/FacebookSDK" "${BACKUP_DIR}/"
    echo "Backup created at: ${BACKUP_DIR}"
else
    echo "No existing Facebook SDK found to backup"
fi

# Download Facebook SDK
cd "${TEMP_DIR}"
echo "Downloading Facebook Unity SDK v${FACEBOOK_VERSION}..."

# Try different possible download URLs (Facebook distributes as .zip files)
URLS=(
    "https://github.com/facebook/facebook-sdk-for-unity/releases/download/sdk-version-${FACEBOOK_VERSION}/facebook-unity-sdk-${FACEBOOK_VERSION}.zip"
    "https://github.com/facebook/facebook-sdk-for-unity/releases/download/v${FACEBOOK_VERSION}/facebook-unity-sdk-${FACEBOOK_VERSION}.zip"
    "https://github.com/facebook/facebook-sdk-for-unity/releases/download/${FACEBOOK_VERSION}/facebook-unity-sdk-${FACEBOOK_VERSION}.zip"
)

DOWNLOAD_SUCCESS=false
for url in "${URLS[@]}"; do
    echo "Trying: ${url}"
    if curl -L -f -o "facebook-unity-sdk-${FACEBOOK_VERSION}.zip" "${url}"; then
        DOWNLOAD_SUCCESS=true
        echo "Download successful from: ${url}"
        break
    else
        echo "Failed to download from: ${url}"
    fi
done

if [[ "${DOWNLOAD_SUCCESS}" != "true" ]]; then
    echo "ERROR: Failed to download Facebook SDK v${FACEBOOK_VERSION} from all URLs"
    echo "Please check the version number and try again."
    echo "Available versions can be found at: https://github.com/facebook/facebook-sdk-for-unity/releases"
    exit 1
fi

# Extract the ZIP file to find the .unitypackage
echo "Extracting Facebook SDK ZIP file..."
unzip -q "facebook-unity-sdk-${FACEBOOK_VERSION}.zip"

# Find the .unitypackage file
UNITYPACKAGE_FILE=$(find . -name "*.unitypackage" -type f | head -1)
if [[ -z "${UNITYPACKAGE_FILE}" ]]; then
    echo "ERROR: No .unitypackage file found in the extracted ZIP"
    echo "Contents of extracted ZIP:"
    ls -la
    exit 1
fi

echo "Found Unity package: ${UNITYPACKAGE_FILE}"

# Import the new Facebook SDK (this will overwrite the existing one)
echo "Importing Facebook Unity SDK v${FACEBOOK_VERSION}..."
"${UNITY_PATH}" -batchmode -quit \
    -projectPath "${PROJECT_PATH}" \
    -importPackage "${TEMP_DIR}/${UNITYPACKAGE_FILE}" \
    -logFile /tmp/unity_facebook_import.log

# Check if import was successful
if [[ $? -eq 0 ]]; then
    echo "Facebook SDK import completed successfully"
    
    # Update Dependencies.xml version references
    DEPS_FILE="${PROJECT_PATH}/Assets/FacebookSDK/Plugins/Editor/Dependencies.xml"
    if [[ -f "${DEPS_FILE}" ]]; then
        echo "Updating iOS pod versions in Dependencies.xml..."
        # Extract major.minor from version (e.g., 19.0 from 19.0.0)
        MAJOR_MINOR=$(echo "${FACEBOOK_VERSION}" | cut -d'.' -f1,2)
        sed -i.bak "s/version=\"~> [0-9]*\.[0-9]*\.[0-9]*\"/version=\"~> ${FACEBOOK_VERSION}\"/g" "${DEPS_FILE}"
        sed -i.bak "s/version=\"~> [0-9]*\.[0-9]*\"/version=\"~> ${MAJOR_MINOR}\"/g" "${DEPS_FILE}"
        rm -f "${DEPS_FILE}.bak"
        echo "Updated pod versions to ~> ${FACEBOOK_VERSION}"
    fi
    
    # Check current FacebookSettings
    SETTINGS_FILE="${PROJECT_PATH}/Assets/FacebookSDK/SDK/Resources/FacebookSettings.asset"
    if [[ -f "${SETTINGS_FILE}" ]]; then
        echo "Facebook SDK settings file found at: ${SETTINGS_FILE}"
        echo "Make sure to configure your Facebook App ID and other settings if needed"
    fi
    
    echo "=== Facebook SDK Update Complete ==="
    echo "Updated from backup at: ${BACKUP_DIR}"
    echo "New SDK version: ${FACEBOOK_VERSION}"
    echo "Import log: /tmp/unity_facebook_import.log"
    
else
    echo "ERROR: Facebook SDK import failed"
    echo "Restoring from backup..."
    
    # Restore from backup
    if [[ -d "${BACKUP_DIR}/FacebookSDK" ]]; then
        cp -r "${BACKUP_DIR}/FacebookSDK" "${PROJECT_PATH}/Assets/"
        echo "Restored Facebook SDK from backup"
    fi
    
    echo "Check import log for details: /tmp/unity_facebook_import.log"
    exit 1
fi

# Clean up temporary files
echo "Cleaning up temporary files..."
rm -rf "${TEMP_DIR}"

# Optional: Clean up backup after successful update
echo "Keep backup? (y/n) [y]: "
read -r keep_backup
if [[ "${keep_backup}" == "n" || "${keep_backup}" == "N" ]]; then
    rm -rf "${BACKUP_DIR}"
    echo "Backup removed"
else
    echo "Backup kept at: ${BACKUP_DIR}"
fi

echo
echo "=== Post-Update Checklist ==="
echo "1. Check FacebookSettings.asset for your App ID configuration"
echo "2. Verify iOS pod versions in Dependencies.xml"
echo "3. Test Facebook login functionality"
echo "4. Check Unity console for any import warnings/errors"
echo "5. Update your ApplePostProcess.cs if framework versions changed"
echo
echo "Current Facebook iOS Pods should be v${FACEBOOK_VERSION}:"
echo "- FBSDKCoreKit"
echo "- FBSDKCoreKit_Basics" 
echo "- FBSDKLoginKit"
echo "- FBSDKShareKit"
echo "- FBSDKGamingServicesKit"
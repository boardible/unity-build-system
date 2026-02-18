# CI/CD Environment Variables Configuration

This document outlines all the required environment variables for building and deploying your Unity project using the modernized build scripts.

## Required Environment Variables

### Universal Variables
```bash
# Unity Configuration
UNITY_BUILD_MODE=development  # or "release"
UNITY_LICENSE_FILE_PATH=/path/to/Unity_lic.ulf  # Unity license file
```

### iOS Variables
```bash
# Apple Developer Configuration
APPLE_DEVELOPER_EMAIL=developer@boardible.com
APPLE_CONNECT_EMAIL=support@boardible.com
APPLE_TEAM_ID=35W3RB2M4Z
APPLE_TEAM_NAME="Boardible LTDA"

# App Store Connect API
APPSTORE_KEY_ID=ABC123DEF4
APPSTORE_ISSUER_ID=12345678-1234-1234-1234-123456789abc
APPSTORE_P8_CONTENT="-----BEGIN PRIVATE KEY-----
MIGTAgEAMBMGByqGSM49...
-----END PRIVATE KEY-----"

# Code Signing
MATCH_PASSWORD=your_match_password_here
REPO_TOKEN=ghp_your_github_token_here

# App Configuration
IOS_APP_ID=com.boardible.ineuj
```

### Android Variables
```bash
# Google Play Store
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON='{
  "type": "service_account",
  "project_id": "your-project",
  "private_key_id": "...",
  "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
  "client_email": "service-account@project.iam.gserviceaccount.com",
  "client_id": "...",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token"
}'

# Android App Configuration
ANDROID_PACKAGE_NAME=com.boardible.ineuj

# Facebook SDK Configuration
FB_APP_ID=your_facebook_app_id
FB_CLIENT_TOKEN=your_facebook_client_token

# Code Signing
# For CI/CD: Use ANDROID_KEYSTORE_BASE64 (base64-encoded keystore file)
# For local: Use ANDROID_KEYSTORE_PATH (path to keystore file)
ANDROID_KEYSTORE_BASE64=base64_encoded_keystore_content
ANDROID_KEYSTORE_PATH=/path/to/your/keystore.jks
ANDROID_KEYSTORE_PASS=your_keystore_password
ANDROID_KEY_ALIAS=your_key_alias
ANDROID_KEY_PASS=your_key_password

# Deployment Configuration (optional)
DEPLOY_TRACK=production  # or "internal", "alpha", "beta"
```

## GitHub Actions Example

Create `.github/workflows/build-and-deploy.yml`:

```yaml
name: Build and Deploy Unity Project

on:
  push:
    branches: [ main, iosBuild, androidBuild ]
  workflow_dispatch:
    inputs:
      platform:
        description: 'Platform to build'
        required: true
        default: 'both'
        type: choice
        options:
        - ios
        - android
        - both
      deploy:
        description: 'Deploy after build'
        required: true
        default: false
        type: boolean

env:
  UNITY_VERSION: "6000.3.7f1"

jobs:
  build:
    runs-on: macos-latest
    strategy:
      matrix:
        platform: 
          - ${{ github.event.inputs.platform == 'both' && 'ios' || github.event.inputs.platform }}
          - ${{ github.event.inputs.platform == 'both' && 'android' || '' }}
        exclude:
          - platform: ''
    
    steps:
    - name: Checkout Repository
      uses: actions/checkout@v4
      
    - name: Setup Unity
      uses: game-ci/unity-builder@v4
      env:
        UNITY_LICENSE: ${{ secrets.UNITY_LICENSE_FILE_CONTENT }}
      with:
        unityVersion: ${{ env.UNITY_VERSION }}
        
    - name: Setup Environment Variables
      run: |
        # Universal
        echo "UNITY_BUILD_MODE=release" >> $GITHUB_ENV
        
        # iOS
        echo "APPLE_DEVELOPER_EMAIL=${{ secrets.APPLE_DEVELOPER_EMAIL }}" >> $GITHUB_ENV
        echo "APPLE_TEAM_ID=${{ secrets.APPLE_TEAM_ID }}" >> $GITHUB_ENV
        echo "APPLE_TEAM_NAME=${{ secrets.APPLE_TEAM_NAME }}" >> $GITHUB_ENV
        echo "APPSTORE_KEY_ID=${{ secrets.APPSTORE_KEY_ID }}" >> $GITHUB_ENV
        echo "APPSTORE_ISSUER_ID=${{ secrets.APPSTORE_ISSUER_ID }}" >> $GITHUB_ENV
        echo "APPSTORE_P8_CONTENT=${{ secrets.APPSTORE_P8_CONTENT }}" >> $GITHUB_ENV
        echo "MATCH_PASSWORD=${{ secrets.MATCH_PASSWORD }}" >> $GITHUB_ENV
        echo "REPO_TOKEN=${{ secrets.REPO_TOKEN }}" >> $GITHUB_ENV
        echo "IOS_APP_ID=com.boardible.ineuj" >> $GITHUB_ENV
        
        # Android
        echo "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON=${{ secrets.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON }}" >> $GITHUB_ENV
        echo "ANDROID_PACKAGE_NAME=com.boardible.ineuj" >> $GITHUB_ENV
        echo "ANDROID_KEYSTORE_PATH=${{ github.workspace }}/android.keystore" >> $GITHUB_ENV
        echo "ANDROID_KEYSTORE_PASS=${{ secrets.ANDROID_KEYSTORE_PASS }}" >> $GITHUB_ENV
        echo "ANDROID_KEY_ALIAS=${{ secrets.ANDROID_KEY_ALIAS }}" >> $GITHUB_ENV
        echo "ANDROID_KEY_PASS=${{ secrets.ANDROID_KEY_PASS }}" >> $GITHUB_ENV
        
    - name: Setup Android Keystore
      if: matrix.platform == 'android'
      run: |
        echo "${{ secrets.ANDROID_KEYSTORE_BASE64 }}" | base64 --decode > android.keystore
        
    - name: Make Scripts Executable
      run: |
        chmod +x Scripts/unityBuild.sh
        chmod +x Scripts/iosDeploy.sh
        chmod +x Scripts/androidDeploy.sh
        
    - name: Build Unity Project
      run: |
        ./Scripts/unityBuild.sh --platform ${{ matrix.platform }} --release
        
    - name: Upload Build Artifacts
      uses: actions/upload-artifact@v4
      with:
        name: build-${{ matrix.platform }}
        path: build/
        
    - name: Deploy iOS
      if: matrix.platform == 'ios' && (github.event.inputs.deploy == 'true' || github.ref == 'refs/heads/iosBuild')
      run: |
        ./Scripts/iosDeploy.sh
        
    - name: Deploy Android
      if: matrix.platform == 'android' && (github.event.inputs.deploy == 'true' || github.ref == 'refs/heads/androidBuild')
      run: |
        ./Scripts/androidDeploy.sh
```

## GitLab CI Example

Create `.gitlab-ci.yml`:

```yaml
stages:
  - build
  - deploy

variables:
  UNITY_VERSION: "6000.3.7f1"
  UNITY_BUILD_MODE: "release"

.unity_before_script: &unity_before_script
  - chmod +x Scripts/unityBuild.sh Scripts/iosDeploy.sh Scripts/androidDeploy.sh
  - echo "$UNITY_LICENSE_FILE_CONTENT" | base64 --decode > Unity.ulf

build_ios:
  stage: build
  tags:
    - macos
  before_script:
    - *unity_before_script
  script:
    - ./Scripts/unityBuild.sh --platform ios --release
  artifacts:
    paths:
      - build/
    expire_in: 1 hour
  only:
    - main
    - iosBuild

build_android:
  stage: build
  tags:
    - macos
  before_script:
    - *unity_before_script
    - echo "$ANDROID_KEYSTORE_BASE64" | base64 --decode > android.keystore
    - export ANDROID_KEYSTORE_PATH="$PWD/android.keystore"
  script:
    - ./Scripts/unityBuild.sh --platform android --release
  artifacts:
    paths:
      - build/
    expire_in: 1 hour
  only:
    - main
    - androidBuild

deploy_ios:
  stage: deploy
  tags:
    - macos
  dependencies:
    - build_ios
  script:
    - ./Scripts/iosDeploy.sh
  only:
    - iosBuild

deploy_android:
  stage: deploy
  tags:
    - macos
  dependencies:
    - build_android
  script:
    - ./Scripts/androidDeploy.sh
  only:
    - androidBuild
```

## Local Development Setup

For local development, create a `.env` file in your project root:

```bash
# .env file (DO NOT COMMIT TO VERSION CONTROL)

# Unity
UNITY_BUILD_MODE=development

# iOS (get from Apple Developer Account)
APPLE_DEVELOPER_EMAIL=your-email@boardible.com
APPLE_TEAM_ID=35W3RB2M4Z
APPLE_TEAM_NAME="Boardible LTDA"
APPSTORE_KEY_ID=your_key_id
APPSTORE_ISSUER_ID=your_issuer_id
APPSTORE_P8_CONTENT="your_p8_content_here"
MATCH_PASSWORD=your_match_password
REPO_TOKEN=your_github_token
IOS_APP_ID=com.boardible.ineuj

# Android (get from Google Play Console)
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON='{"type":"service_account",...}'
ANDROID_PACKAGE_NAME=com.boardible.ineuj
ANDROID_KEYSTORE_PATH=/path/to/your/keystore.jks
ANDROID_KEYSTORE_PASS=your_keystore_password
ANDROID_KEY_ALIAS=your_key_alias
ANDROID_KEY_PASS=your_key_password
```

Then source it before running scripts:
```bash
source .env  # Load environment variables
./Scripts/unityBuild.sh --platform both --release
```

## Migration Guide

### From Old System
1. **Remove encrypted files**: Delete `secret.enc`, `secret.txt`, and related files
2. **Set up environment variables**: Configure all variables in your CI/CD system
3. **Update scripts**: Use the new modernized scripts
4. **Test builds**: Run test builds to ensure everything works

### Security Improvements
- ✅ No more plain text secrets in repositories
- ✅ No more manual password entry
- ✅ Proper secret rotation via CI/CD
- ✅ Centralized secret management
- ✅ Audit trail for secret usage

### Troubleshooting
- **Missing variables**: Scripts will fail fast with clear error messages
- **Wrong values**: Check your CI/CD secret configuration
- **Build failures**: Check Unity logs in the `Logs/` directory
- **Deploy failures**: Check Fastlane logs for detailed error information
# Unity Build System Configuration
# Copy this file to your Unity project root and customize the values for your project

# Project Settings
export PROJECT_NAME="YourUnityProject"
export UNITY_VERSION="6000.2.14f1"

# iOS Configuration  
export IOS_APP_ID="com.yourcompany.yourapp"
export APPLE_CONNECT_EMAIL="your-email@yourcompany.com"
export MATCH_REPOSITORY="yourorg/matchCertificate"

# Android Configuration
export ANDROID_PACKAGE_NAME="com.yourcompany.yourapp"

# Build Paths (relative to project root)
export UNITY_PROJECT_PATH="."
export BUILD_OUTPUT_PATH="build"

# CI/CD Settings
export DEPLOY_TRACK="production"  # For Android: internal, alpha, beta, production

# Optional: Override default artifact names
# export IOS_ARTIFACT_NAME="ios-build"
# export ANDROID_ARTIFACT_NAME="android-build"

# Optional: Custom build arguments
# export UNITY_BUILD_ARGS=""
# export FASTLANE_ENV="default"
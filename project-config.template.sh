# Unity Build System Configuration
# Copy this file to your Unity project root and customize the values for your project

# Project Settings
export PROJECT_NAME="YourUnityProject"
export UNITY_VERSION="6000.3.7f1"

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

# BoardDoctor Settings
export BOARD_DOCTOR_URL="https://api.boardible.com/board-doctor"
export BOARD_DOCTOR_TOKEN=""  # Set via environment or CI secrets

# CSV Sync Settings
export CSV_SYNC_ENABLED="true"
export S3_BUCKET="your-csv-bucket"
export CLOUDFRONT_DOMAIN="csv.yourcompany.com"

# Remote Addressables Settings
# Set REMOTE_ADDRESSABLES_ENABLED=true only for projects that host Addressables on a CDN
export REMOTE_ADDRESSABLES_ENABLED="false"
# export ADDRESSABLES_S3_PATH="s3://your-cdn-bucket/addressables_test"  # Required when enabled
# export ADDRESSABLES_CLOUDFRONT_DISTRIBUTION_ID=""                     # Set via environment or CI secrets
# Unity Build System Integration Guide

This guide explains how to integrate the Universal Unity Build System into your Unity projects.

## 🎯 Overview

The Unity Build System is designed as a **git submodule** that provides:
- Unified build scripts for iOS and Android
- Modern CI/CD pipeline with GitHub Actions
- Secure environment variable-based secret management
- Cost-efficient selective branch building

## 📦 Step-by-Step Integration

### 1. Add Submodule to Your Project

```bash
# Navigate to your Unity project root
cd your-unity-project

# Add the build system as a submodule
git submodule add https://github.com/boardible/unity-build-system.git Scripts

# Initialize and update the submodule
git submodule update --init --recursive
```

### 2. Create Project Configuration

```bash
# Copy the configuration template
cp Scripts/project-config.template.sh project-config.sh

# Edit with your project details
nano project-config.sh
```

**Example configuration:**
```bash
# Project Settings
export PROJECT_NAME="MyAwesomeGame"
export UNITY_VERSION="6000.0.58f2"

# iOS Configuration  
export IOS_APP_ID="com.mycompany.awesomegame"
export APPLE_CONNECT_EMAIL="developer@mycompany.com"
export MATCH_REPOSITORY="mycompany/matchCertificate"

# Android Configuration
export ANDROID_PACKAGE_NAME="com.mycompany.awesomegame"
```

### 3. Setup GitHub Actions

```bash
# Create workflows directory
mkdir -p .github/workflows

# Copy the workflow template
cp Scripts/.github-workflow-template.yml .github/workflows/unity-build.yml

# Customize if needed (usually no changes required)
```

### 4. Configure GitHub Secrets

Use the provided scripts to set up your GitHub secrets:

```bash
# Check what secrets you need
./Scripts/checkSecrets.sh

# Interactive secret setup
./Scripts/setupSecrets.sh

# Or setup Google Play JSON specifically
./Scripts/setupGooglePlaySecret.sh
```

**Required Secrets:**
- `UNITY_LICENSE` - Your Unity license file content
- `APPLE_DEVELOPER_EMAIL`, `APPLE_TEAM_ID`, `APPSTORE_KEY_ID`, etc. (iOS)
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`, `ANDROID_KEYSTORE_BASE64`, etc. (Android)

### 5. Setup Fastlane (Required for Deployment)

```bash
# Initialize Fastlane in your project root
bundle init
echo 'gem "fastlane"' >> Gemfile
bundle install

# Initialize Fastlane
bundle exec fastlane init
```

Follow the Fastlane setup for both iOS and Android platforms.

### 6. Create Build Branches

```bash
# Create iOS build branch
git checkout -b iosBuild
git push -u origin iosBuild

# Create Android build branch  
git checkout -b androidBuild
git push -u origin androidBuild

# Return to main
git checkout main
```

### 7. Test Your Setup

```bash
# Test iOS build locally (optional)
./Scripts/setupLocalIOS.sh --create-env
# Edit .env.ios.local with your credentials
./Scripts/setupLocalIOS.sh --deploy

# Test by pushing to build branches
git checkout androidBuild
git merge main
git push origin androidBuild  # Triggers Android build in CI/CD
```

## 🔄 Daily Workflow

### Development
```bash
# Work on main branch (no CI/CD costs)
git checkout main
# ... make changes, commit ...
git push origin main  # No builds triggered
```

### Testing Builds
```bash
# When ready to test Android build
git checkout androidBuild
git merge main
git push origin androidBuild  # Triggers Android build + deploy

# When ready to test iOS build  
git checkout iosBuild
git merge main
git push origin iosBuild  # Triggers iOS build + deploy
```

### Production Release
```bash
# Create and push release tag
git tag v1.0.0
git push origin v1.0.0

# Create GitHub release
# This triggers both iOS and Android builds
```

## 🎮 Multiple Projects

### Sharing Across Games

Each of your Unity projects can use the same build system:

```bash
# Project 1
cd game-one
git submodule add https://github.com/boardible/unity-build-system.git Scripts

# Project 2  
cd ../game-two
git submodule add https://github.com/boardible/unity-build-system.git Scripts

# Project 3
cd ../game-three
git submodule add https://github.com/boardible/unity-build-system.git Scripts
```

Each project gets its own `project-config.sh` with project-specific settings.

### Updating the Build System

When the build system is updated:

```bash
# In any project using the submodule
git submodule update --remote Scripts
git add Scripts
git commit -m "Updated build system"
```

## 🛠️ Customization

### Custom Build Steps

Add project-specific build steps by creating hooks in your project root:

```bash
# pre-build.sh - runs before Unity build
#!/bin/bash
echo "Running custom pre-build steps..."

# post-build.sh - runs after Unity build  
#!/bin/bash
echo "Running custom post-build steps..."
```

The build system will automatically detect and run these hooks.

### Custom Fastlane Actions

Extend the Fastlane configuration in your project's `Fastfile`:

```ruby
# fastlane/Fastfile
platform :ios do
  lane :beta do
    # Custom iOS deployment logic
  end
end

platform :android do  
  lane :internal do
    # Custom Android deployment logic
  end
end
```

## 🚨 Troubleshooting

### Common Issues

1. **Submodule not updating**: `git submodule update --remote`
2. **Unity license issues**: Ensure `UNITY_LICENSE` secret is set correctly
3. **Fastlane errors**: Check that Fastlane is properly configured for your project
4. **Build branch not triggering**: Verify GitHub Actions workflow is committed

### Getting Help

1. Check the build system logs in GitHub Actions
2. Use `./Scripts/checkSecrets.sh` to verify secret configuration
3. Test locally with `./Scripts/setupLocalIOS.sh`

## 📚 Advanced Topics

### Branch Protection Rules

Recommended branch protection for cost control:

- `main`: Require PR reviews, no direct pushes
- `iosBuild`: Allow direct pushes for build testing  
- `androidBuild`: Allow direct pushes for build testing

### Environment-Specific Builds

You can have different deployment tracks:

```bash
# In project-config.sh
export DEPLOY_TRACK="internal"  # For testing
# or
export DEPLOY_TRACK="production"  # For live release
```

This allows you to have separate workflows for testing vs production builds.
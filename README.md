# Universal Unity Build System

This is a reusable build and deployment system for Unity projects. The system uses modern CI/CD practices with environment variables instead of encrypted files, and can be easily integrated into any Unity project as a git submodule.

## 🚀 Features

- **Universal**: Works with any Unity project via configuration
- **Secure**: Environment variable-based secret management
- **Complete**: Build → Deploy → App Stores in one pipeline
- **Cost-Efficient**: Selective branch triggering
- **Modern**: Clean, maintainable scripts with proper error handling
- **Reusable**: Designed as a git submodule for multiple projects

## 📁 Integration as Submodule

### Adding to Your Unity Project

```bash
# Navigate to your Unity project root
cd your-unity-project

# Add this as a submodule
git submodule add https://github.com/boardible/unity-build-system.git Scripts

# Copy and customize the configuration
cp Scripts/project-config.template.sh project-config.sh
# Edit project-config.sh with your project details

# Copy the GitHub Actions workflow
mkdir -p .github/workflows
cp Scripts/.github-workflow-template.yml .github/workflows/unity-build.yml
```

### Configuration

Create a `project-config.sh` file in your project root:

```bash
# Project Settings
export PROJECT_NAME="YourGameName"
export UNITY_VERSION="6000.0.58f2"

# iOS Configuration  
export IOS_APP_ID="com.yourcompany.yourgame"
export APPLE_CONNECT_EMAIL="your-email@yourcompany.com"
export MATCH_REPOSITORY="yourorg/matchCertificate"

# Android Configuration
export ANDROID_PACKAGE_NAME="com.yourcompany.yourgame"
```

## Prerequisites

- Unity (any recent version)
- Xcode (for iOS builds)
- Android SDK (for Android builds)
- Ruby with Bundler (for Fastlane)

### Build Commands

```bash
# Build iOS only
./Scripts/unityBuild.sh --platform ios

# Build Android only  
./Scripts/unityBuild.sh --platform android

# Build both platforms
./Scripts/unityBuild.sh --platform both

# Build in release mode
./Scripts/unityBuild.sh --platform both --release
```

### Deploy Commands

```bash
# Deploy iOS to TestFlight
./Scripts/iosDeploy.sh

# Deploy Android to Play Store
./Scripts/androidDeploy.sh
```

## File Structure

```
Scripts/
├── unityBuild.sh                    # Main Unity build script
├── iosDeploy.sh                     # iOS deployment script  
├── androidDeploy.sh                 # Android deployment script
├── CI-CD-ENVIRONMENT-VARIABLES.md   # Environment variable documentation
├── README.md                        # This file
└── legacy/                          # Old scripts (deprecated)
    ├── cicdBuild.sh
    ├── cicdIosBuild.sh
    └── cicdAndroidBuild.sh

Assets/Editor/
└── BuildScript.cs                   # Unity C# build methods
```

## New Features

### ✅ Unified Build System
- Single script handles both iOS and Android builds
- Actual Unity build commands (no more git-based triggers)
- Proper error handling and logging
- Addressables building integrated

### ✅ Modern Secret Management
- Uses CI/CD environment variables
- No more encrypted files or manual password entry
- Secure and auditable secret handling
- Easy secret rotation

### ✅ Better Error Handling
- Scripts fail fast with clear error messages
- Detailed logging with timestamps
- Build artifacts preservation
- Proper cleanup on failure

### ✅ CI/CD Ready
- GitHub Actions examples provided
- GitLab CI configuration included
- Environment variable validation
- Artifact handling

## Migration from Old System

### What Changed
- **Removed**: Encrypted secret files (`secret.enc`)
- **Removed**: Manual password prompts
- **Removed**: Git-based build triggering
- **Added**: Actual Unity build commands
- **Added**: Environment variable validation
- **Added**: Proper logging and error handling

### Migration Steps
1. **Set up environment variables** (see CI-CD-ENVIRONMENT-VARIABLES.md)
2. **Update CI/CD pipelines** to use new scripts
3. **Test builds locally** with new system
4. **Remove old encrypted files** from repository
5. **Update team documentation**

## Environment Variables

See `CI-CD-ENVIRONMENT-VARIABLES.md` for complete documentation.

### Required for iOS
- `APPLE_TEAM_ID`
- `APPSTORE_KEY_ID`
- `APPSTORE_ISSUER_ID` 
- `APPSTORE_P8_CONTENT`
- `MATCH_PASSWORD`
- `REPO_TOKEN`

### Required for Android
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`
- `ANDROID_KEYSTORE_PATH`
- `ANDROID_KEYSTORE_PASS`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASS`

## Troubleshooting

### Common Issues

**"Unity not found"**
- Update `UNITY_PATH` in `unityBuild.sh`
- Ensure Unity 6000.0.58f2 is installed

**"Missing environment variables"**
- Check CI-CD-ENVIRONMENT-VARIABLES.md
- Verify all required variables are set
- For local development, create and source a `.env` file

**"Build failed"**
- Check Unity logs in `Logs/` directory
- Verify Unity license is valid
- Check platform-specific requirements (Xcode, Android SDK)

**"Deployment failed"**
- Check Fastlane logs
- Verify App Store Connect API key
- Verify Google Play Service Account permissions

### Getting Help

1. Check the logs in `Logs/` directory
2. Review environment variable configuration
3. Test with a simple development build first
4. Check Unity console for additional error details

## Development Workflow

### Local Development
```bash
# Set up environment variables
source .env

# Build for testing
./Scripts/unityBuild.sh --platform ios
./Scripts/unityBuild.sh --platform android

# Deploy to stores (if needed)
./Scripts/iosDeploy.sh
./Scripts/androidDeploy.sh
```

### CI/CD Pipeline
```bash
# Triggered by branch push
git push origin main:iosBuild     # Triggers iOS build
git push origin main:androidBuild # Triggers Android build
```

## Security Best Practices

### ✅ Do's
- Use CI/CD environment variables for secrets
- Rotate secrets regularly
- Use service accounts with minimal permissions
- Keep build logs secure
- Audit secret access

### ❌ Don'ts
- Commit secrets to version control
- Use personal accounts for CI/CD
- Share secrets via insecure channels
- Leave temporary files with secrets
- Use the same secrets across environments

## Performance Optimizations

### Build Performance
- Addressables are built once per platform
- Unity builds use IL2CPP for better performance
- Proper caching of build artifacts
- Parallel builds when possible

### Deploy Performance
- Fastlane handles upload optimization
- Mapping files included for crash reporting
- Symbol files properly generated
- Build validation before upload

## Maintenance

### Regular Tasks
- Update Unity version in scripts when upgrading
- Rotate secrets every 90 days
- Review and update dependencies
- Monitor build performance
- Update CI/CD pipeline as needed

### Version Updates
When updating Unity version:
1. Update `UNITY_VERSION` in CI/CD configurations
2. Test builds thoroughly
3. Update documentation
4. Verify all packages still compatible

## Support

For issues with the build system:
1. Check this documentation first
2. Review error logs
3. Test with minimal configuration
4. Check Unity and platform-specific requirements
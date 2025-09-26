# CI/CD Branch Strategy

## Cost-Efficient Build Triggers

To minimize CI/CD costs, builds are **only triggered** on specific branches:

### Build Triggers ✅
- **`androidBuild`** - Triggers Android build only
- **`iosBuild`** - Triggers iOS build only
- **Manual dispatch** - Can build either platform via GitHub Actions UI
- **Releases** - Builds both platforms when creating a GitHub release

### No Build Triggers ❌
- **`main`** - No builds triggered (cost savings)
- **`develop`** - No builds triggered
- **Feature branches** - No builds triggered
- **Pull requests** - No builds triggered

## Workflow Examples

### Android Development
```bash
# Work on your feature
git checkout -b feature/new-android-feature
# ... make changes ...
git commit -m "Add new feature"

# When ready to build and test
git checkout androidBuild
git merge feature/new-android-feature
git push origin androidBuild
# ✅ Triggers Android build
```

### iOS Development
```bash
# Work on your feature
git checkout -b feature/new-ios-feature
# ... make changes ...
git commit -m "Add new feature"

# When ready to build and test
git checkout iosBuild
git merge feature/new-ios-feature
git push origin iosBuild
# ✅ Triggers iOS build
```

### Production Release
```bash
# Merge tested features to main
git checkout main
git merge feature/ready-feature
git push origin main
# ❌ No build triggered (cost savings)

# Create release to build both platforms
git tag v1.2.3
git push origin v1.2.3
# Then create GitHub release
# ✅ Triggers both iOS and Android builds
```

### Manual Builds
You can also trigger builds manually from GitHub Actions:
1. Go to Actions tab in GitHub
2. Select "Modern Unity CI/CD Pipeline"
3. Click "Run workflow"
4. Choose platform (iOS, Android, or both)

## Branch Protection

Consider setting up branch protection rules:
- `main` - Require PR reviews, no direct pushes
- `androidBuild` - Allow direct pushes for build testing
- `iosBuild` - Allow direct pushes for build testing

This strategy ensures:
- 💰 **Cost savings** - No accidental builds on main
- 🔄 **Efficient testing** - Dedicated build branches
- 🚀 **Production ready** - Release-triggered builds
- 🛡️ **Quality control** - Protected main branch
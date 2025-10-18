# Self-Hosted GitHub Actions Runner Setup Guide

## Overview
This guide will help you set up your Windows PC notebook as a self-hosted GitHub Actions runner for Android builds, eliminating ~$40-56/month in CI/CD costs.

**Time Required**: ~30 minutes  
**Cost Savings**: 43% reduction ($88-128/month → $48-72/month)  
**Strategy**: Self-hosted Android (free) + GitHub Actions iOS ($48-72/month)

---

## Prerequisites

### Required
- ✅ Windows PC notebook (any specs - Unity Android builds are not intensive)
- ✅ Stable internet connection
- ✅ Administrator access (for Windows service installation)
- ✅ At least 20GB free disk space (Unity + Android SDK + runner)

### Installed Software
- ✅ Unity Hub with Unity 6000.2.6f2
- ✅ Android Build Support module for Unity 6000.2.6f2
- ✅ PowerShell 5.1 or later (pre-installed on Windows 10/11)

### Verify Unity Installation
```powershell
# Check if Unity 6000.2.6f2 is installed
Get-ChildItem -Path "C:\Program Files\Unity\Hub\Editor" -Filter "6000.2.6f2" -Directory
# OR
Get-ChildItem -Path "$env:ProgramFiles\Unity\Hub\Editor" -Filter "6000.2.6f2" -Directory
```

If Unity is not installed, download from Unity Hub or visit:
https://unity.com/releases/editor/whats-new/6000.2.6

---

## Step 1: Get GitHub Registration Token

1. **Navigate to GitHub Runner Settings**:
   - Direct link: https://github.com/boardible/ineuj/settings/actions/runners/new
   - Or manually: Repository → Settings → Actions → Runners → New self-hosted runner

2. **Select Platform**:
   - Choose **Windows** as the operating system
   - Choose **x64** as the architecture

3. **Copy Registration Token**:
   - Look for a section labeled "Configure"
   - Find the command with `--token` parameter
   - Copy the token value (format: `A23XYZ...` - very long alphanumeric string)
   - **⚠️ IMPORTANT**: Token expires after a few hours and is single-use

---

## Step 2: Transfer Setup Script to Windows PC

Choose one of these methods:

### Option A: Git Pull (Recommended)
```powershell
# On your Windows PC
cd C:\Dev  # or your preferred dev folder
git clone https://github.com/boardible/ineuj.git
cd ineuj
git pull origin main  # get latest scripts
```

### Option B: Direct Download
1. Open this file in browser:
   https://github.com/boardible/ineuj/blob/main/Scripts/setupSelfHostedRunner-Windows.ps1
2. Click "Raw" button
3. Right-click → Save As → `setupSelfHostedRunner-Windows.ps1`
4. Save to `C:\Dev\ineuj\Scripts\` (create folders if needed)

### Option C: Copy-Paste
1. Copy the script content from your Mac:
   ```bash
   cat /Users/pedromartinez/Dev/ineuj/Scripts/setupSelfHostedRunner-Windows.ps1 | pbcopy
   ```
2. Paste into Notepad on Windows and save as:
   `C:\Dev\ineuj\Scripts\setupSelfHostedRunner-Windows.ps1`

---

## Step 3: Run Setup Script

### Open PowerShell as Administrator
1. Press `Win + X`
2. Select "Windows PowerShell (Admin)" or "Windows Terminal (Admin)"
3. Click "Yes" on UAC prompt

### Navigate to Script Location
```powershell
cd C:\Dev\ineuj\Scripts
```

### View Script Help (Optional)
```powershell
.\setupSelfHostedRunner-Windows.ps1 -Help
```

### Run the Setup
```powershell
# Replace YOUR_TOKEN_HERE with the token from Step 1
.\setupSelfHostedRunner-Windows.ps1 -GitHubToken "YOUR_TOKEN_HERE"
```

**Example**:
```powershell
.\setupSelfHostedRunner-Windows.ps1 -GitHubToken "A23XYZ4567ABCDEF890123HIJKLMN456789OPQRSTUV"
```

### Optional Parameters
```powershell
# Custom runner name
.\setupSelfHostedRunner-Windows.ps1 -GitHubToken "TOKEN" -RunnerName "MyCustomRunner"

# Skip Unity verification (if Unity is in non-standard location)
.\setupSelfHostedRunner-Windows.ps1 -GitHubToken "TOKEN" -SkipUnityCheck
```

### What the Script Does
1. ✅ Validates GitHub token format
2. ✅ Creates `C:\actions-runner` directory
3. ✅ Downloads GitHub Actions Runner v2.311.0
4. ✅ Extracts runner files
5. ✅ Verifies Unity 6000.2.6f2 installation
6. ✅ Checks Android Build Support module
7. ✅ Configures runner for `boardible/ineuj` repo
8. ✅ Applies labels: `self-hosted`, `windows`, `android`, `unity`
9. ✅ Installs as Windows service (auto-starts on boot)
10. ✅ Starts the runner service

---

## Step 4: Verify Runner is Online

### Check in GitHub
1. Navigate to: https://github.com/boardible/ineuj/settings/actions/runners
2. You should see your runner listed with status **"Idle"** (green dot)
3. Labels should show: `self-hosted`, `windows`, `android`, `unity`

### Check Windows Service
```powershell
# Check service status
Get-Service -Name "actions.runner.*"

# Should show:
# Status   Name               DisplayName
# ------   ----               -----------
# Running  actions.runner.... GitHub Actions Runner (...)
```

### Check Runner Logs
```powershell
cd C:\actions-runner
Get-Content _diag\Runner_*.log -Tail 50
```

Look for messages like:
- ✅ `Connected to GitHub`
- ✅ `Listening for Jobs`
- ✅ `Runner successfully added`

---

## Step 5: Update GitHub Workflow

Now that your runner is online, update the workflow to use it for Android builds:

### Edit `.github/workflows/main.yml`

**Before** (lines 183-185):
```yaml
build_android:
  name: Build for Android
  runs-on: macos-latest  # ❌ Expensive macOS runner
```

**After**:
```yaml
build_android:
  name: Build for Android
  runs-on: [self-hosted, windows, android]  # ✅ Your free Windows PC
```

### Also Fix Unity Version Mismatch

**Before** (line 36):
```yaml
UNITY_VERSION: "6000.2.7f2"  # ❌ Wrong version
```

**After**:
```yaml
UNITY_VERSION: "6000.2.6f2"  # ✅ Matches project version
```

### Commit Changes
```bash
git add .github/workflows/main.yml
git commit -m "Use self-hosted runner for Android builds"
git push origin main
```

---

## Step 6: Test the Setup

### Trigger a Build
1. Push to `androidBuild` branch:
   ```bash
   git checkout androidBuild
   git merge main
   git push origin androidBuild
   ```

2. **OR** manually trigger via GitHub Actions UI:
   - Go to: https://github.com/boardible/ineuj/actions
   - Select your workflow
   - Click "Run workflow"
   - Select branch: `androidBuild`
   - Click "Run workflow"

### Monitor the Build
1. Watch GitHub Actions page: https://github.com/boardible/ineuj/actions
2. You should see "Build for Android" running on your self-hosted runner
3. On your Windows PC, Task Manager should show Unity process running

### Check Runner Logs on Windows
```powershell
cd C:\actions-runner
Get-Content _diag\Worker_*.log -Tail 100 -Wait
```

---

## Cost Comparison

### Before (Current Setup)
- **iOS Build**: macOS runner = $0.08/min × 60min = **$4.80/build**
- **Android Build**: macOS runner = $0.08/min × 70min = **$5.60/build**
- **Monthly** (iOS: 10 builds, Android: 10 builds): **$88-128/month**

### After (Self-Hosted Android)
- **iOS Build**: macOS runner = $0.08/min × 60min = **$4.80/build**
- **Android Build**: Self-hosted = **$0/build** ✅
- **Monthly** (iOS: 10 builds, Android: unlimited): **$48-72/month**

### Savings
- **Monthly**: $40-56 saved (43% reduction)
- **Yearly**: $480-672 saved
- **Hardware Cost**: $0 (using existing PC)

---

## Troubleshooting

### Issue: "Unity 6000.2.6f2 not found"

**Solution 1**: Install Unity 6000.2.6f2
```powershell
# Download Unity Hub
# Open Unity Hub → Installs → Install Editor → Version: 6000.2.6f2
# Select: Android Build Support (required)
```

**Solution 2**: Skip Unity check
```powershell
.\setupSelfHostedRunner-Windows.ps1 -GitHubToken "TOKEN" -SkipUnityCheck
```

### Issue: "Android Build Support not detected"

**Solution**: Add module via Unity Hub
1. Open Unity Hub
2. Go to "Installs"
3. Click gear icon next to Unity 6000.2.6f2
4. Select "Add modules"
5. Check "Android Build Support"
6. Check "Android SDK & NDK Tools"
7. Check "OpenJDK"
8. Click "Install"

### Issue: "Script execution disabled"

**Solution**: Enable script execution
```powershell
# Run as Administrator
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Issue: "Service failed to install"

**Cause**: Not running as Administrator

**Solution**: 
1. Close PowerShell
2. Right-click PowerShell → "Run as Administrator"
3. Re-run script

### Issue: Runner shows "Offline" in GitHub

**Check 1**: Service status
```powershell
Get-Service -Name "actions.runner.*"
# If stopped:
Start-Service -Name "actions.runner.*"
```

**Check 2**: Network connectivity
```powershell
Test-NetConnection -ComputerName github.com -Port 443
```

**Check 3**: Runner logs
```powershell
cd C:\actions-runner
Get-Content _diag\Runner_*.log -Tail 100
```

### Issue: Build fails with "Unity license not activated"

**Solution**: Activate Unity license on Windows PC
```powershell
# Personal license (free)
"C:\Program Files\Unity\Hub\Editor\6000.2.6f2\Editor\Unity.exe" -quit -batchmode -serial "" -username "your@email.com" -password "yourpassword"

# OR use Unity Hub GUI:
# Unity Hub → Preferences → Licenses → Activate New License
```

---

## Maintenance

### Updating the Runner
```powershell
cd C:\actions-runner
.\config.cmd remove --token "NEW_TOKEN"  # Get from GitHub
# Re-run setupSelfHostedRunner-Windows.ps1
```

### Stopping the Runner
```powershell
# Temporary (until reboot)
Stop-Service -Name "actions.runner.*"

# Permanent removal
cd C:\actions-runner
.\config.cmd remove --token "TOKEN"
```

### Viewing Runner Logs
```powershell
# Recent logs
Get-Content C:\actions-runner\_diag\Runner_*.log -Tail 50

# Live logs
Get-Content C:\actions-runner\_diag\Worker_*.log -Tail 100 -Wait

# All logs
Get-ChildItem C:\actions-runner\_diag\*.log | Sort-Object LastWriteTime | Select-Object -Last 5
```

---

## Security Notes

### Token Security
- ✅ Registration tokens expire after a few hours
- ✅ Tokens are single-use (cannot reuse after configuration)
- ✅ Script validates token format before use
- ⚠️ Never commit tokens to git

### Runner Security
- ✅ Runner runs as Windows service with limited permissions
- ✅ Only executes jobs from `boardible/ineuj` repository
- ✅ GitHub validates all workflow files before execution
- ⚠️ Keep Windows updated for security patches
- ⚠️ Use firewall to restrict network access if shared PC

### Network Requirements
- **Outbound HTTPS (443)**: `github.com`, `api.github.com`, `*.actions.githubusercontent.com`
- **Inbound**: None (runner polls GitHub, no incoming connections)

---

## Alternative: Linux/WSL Setup

If you prefer Linux or WSL (Windows Subsystem for Linux):

```bash
# Transfer script to Linux
scp /Users/pedromartinez/Dev/ineuj/Scripts/setupSelfHostedRunner-Linux.sh user@windowspc:/home/user/

# On Linux/WSL
chmod +x setupSelfHostedRunner-Linux.sh
./setupSelfHostedRunner-Linux.sh --token "YOUR_TOKEN" --name "LinuxRunner"
```

Advantages of Linux:
- ✅ Slightly faster Unity builds (~10% faster)
- ✅ Better log management via systemd
- ✅ Easier remote access via SSH

Disadvantages:
- ❌ Requires WSL2 setup on Windows
- ❌ More complex Unity installation on Linux

---

## Next Steps

After successful setup:

1. ✅ **Update workflow file** (Step 5 above)
2. ✅ **Test with actual build** (Step 6 above)
3. ✅ **Monitor first few builds** to ensure stability
4. ✅ **Configure auto-restart** if PC reboots (already done by service)
5. ✅ **Set up remote access** (optional - TeamViewer/AnyDesk for monitoring)

---

## Support

### GitHub Runner Documentation
- https://docs.github.com/en/actions/hosting-your-own-runners

### Unity Build Documentation
- https://docs.unity3d.com/Manual/android-BuildProcess.html

### Project-Specific Help
- See `ARCHITECTURE_REFERENCE.md` for project architecture
- See `Scripts/README.md` for build system details
- Check `.github/workflows/main.yml` for workflow configuration

---

## Summary

🎉 **Congratulations!** You've set up a free self-hosted GitHub Actions runner for Android builds.

**What you've accomplished**:
- ✅ Eliminated $40-56/month in Android build costs
- ✅ Reduced total CI/CD costs by 43%
- ✅ Enabled unlimited Android builds at no cost
- ✅ Maintained iOS builds on GitHub Actions (required for macOS)
- ✅ Created production-ready CI/CD pipeline with hybrid approach

**Next time you push to `androidBuild` branch**:
- Android builds run on your Windows PC (free)
- iOS builds run on GitHub Actions ($4.80/build)
- Total monthly cost: $48-72 (down from $88-128)

🚀 **Happy building!**

# ✅ Self-Hosted Runner Setup - Checklist

Print this or keep it open while setting up your Windows PC.

---

## 📦 Before You Start

### Files You Need
- [ ] `setupSelfHostedRunner-Windows.ps1` (main setup script)
- [ ] `getRunnerToken.ps1` (helper to get token)
- [ ] `QUICK_START.md` (reference guide)

### Prerequisites Verification
- [ ] Windows 10 or 11 installed
- [ ] You have Administrator password
- [ ] Internet connection is stable
- [ ] Unity Hub is installed
- [ ] Unity 6000.2.6f2 is installed
- [ ] Android Build Support module is installed

**Verify Unity Installation**:
```powershell
# Run this in PowerShell to check
Get-ChildItem "C:\Program Files\Unity\Hub\Editor" | Where-Object { $_.Name -eq "6000.2.6f2" }
```

**If Unity missing**: Download Unity Hub → Install → Add 6000.2.6f2 → Android Build Support

---

## 🚀 Setup Process (30 minutes)

### Phase 1: Get GitHub Token (5 minutes)

#### Option A: Automatic Helper
- [ ] Open PowerShell (regular, not Admin)
- [ ] Navigate: `cd C:\Dev\ineuj\Scripts`
- [ ] Run: `.\getRunnerToken.ps1`
- [ ] Browser opens automatically
- [ ] Follow on-screen instructions
- [ ] Copy token from GitHub page

#### Option B: Manual
- [ ] Open browser
- [ ] Go to: https://github.com/boardible/ineuj/settings/actions/runners/new
- [ ] Select "Windows" + "x64"
- [ ] Scroll to "Configure" section
- [ ] Find line with `--token`
- [ ] Copy ONLY the long string after `--token`

**Token looks like**: `A23XYZ4567ABCDEF890123HIJKLMN456789OPQRSTUV...`

---

### Phase 2: Run Setup Script (20 minutes)

- [ ] **IMPORTANT**: Open PowerShell as **Administrator**
  - [ ] Press `Win + X`
  - [ ] Click "Windows PowerShell (Admin)"
  - [ ] Click "Yes" on UAC prompt

- [ ] Navigate to scripts folder:
  ```powershell
  cd C:\Dev\ineuj\Scripts
  ```

- [ ] (Optional) View help:
  ```powershell
  .\setupSelfHostedRunner-Windows.ps1 -Help
  ```

- [ ] Run setup with your token:
  ```powershell
  .\setupSelfHostedRunner-Windows.ps1 -GitHubToken "PASTE_YOUR_TOKEN_HERE"
  ```

**Wait for script to complete** (shows green success messages)

---

### Phase 3: Verify Installation (5 minutes)

#### Check 1: GitHub Website
- [ ] Go to: https://github.com/boardible/ineuj/settings/actions/runners
- [ ] Your runner appears in the list
- [ ] Status shows **"Idle"** with green dot
- [ ] Labels show: `self-hosted`, `windows`, `android`, `unity`

#### Check 2: Windows Service
```powershell
# Check service is running
Get-Service -Name "actions.runner.*"
```
- [ ] Status shows **"Running"**

#### Check 3: Logs
```powershell
# View recent logs
Get-Content C:\actions-runner\_diag\Runner_*.log -Tail 20
```
- [ ] Logs show "Connected to GitHub"
- [ ] Logs show "Listening for Jobs"
- [ ] No error messages

---

## 🔧 Update Workflow File (Back on Mac)

- [ ] Open: `.github/workflows/main.yml`
- [ ] Find line ~179: `build_android:` section
- [ ] Change `runs-on: macos-latest`
- [ ] To: `runs-on: [self-hosted, windows, android]`
- [ ] Verify line ~36: `UNITY_VERSION: "6000.2.6f2"` (already fixed)
- [ ] Save file
- [ ] Commit changes:
  ```bash
  git add .github/workflows/main.yml
  git commit -m "Use self-hosted runner for Android builds"
  git push origin main
  ```

---

## 🧪 Test Build (5 minutes)

- [ ] Push to `androidBuild` branch:
  ```bash
  git push origin androidBuild
  ```

- [ ] Watch GitHub Actions:
  - [ ] Open: https://github.com/boardible/ineuj/actions
  - [ ] See build start
  - [ ] "Build Android" job shows "self-hosted" label

- [ ] Watch on Windows PC:
  - [ ] Open Task Manager
  - [ ] Unity process appears during build
  - [ ] Or watch logs live:
    ```powershell
    Get-Content C:\actions-runner\_diag\Worker_*.log -Tail 100 -Wait
    ```

- [ ] Build completes successfully
- [ ] APK artifact uploaded to GitHub

---

## ✅ Success Criteria

Mark these when you see them:

- [ ] ✅ Runner shows "Idle" in GitHub (green)
- [ ] ✅ Service auto-started (didn't need manual start)
- [ ] ✅ First test build ran on your PC
- [ ] ✅ Build completed successfully
- [ ] ✅ APK uploaded to GitHub Actions artifacts
- [ ] ✅ No cost charged to GitHub Actions (Android build)
- [ ] ✅ Windows PC auto-starts runner after reboot

---

## 🆘 Troubleshooting Quick Reference

### Issue: "Execution policy prevents script"
**Fix**:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Issue: "Unity 6000.2.6f2 not found"
**Fix**:
1. Open Unity Hub
2. Installs → Add → Version 6000.2.6f2
3. Select "Android Build Support"
4. Install

### Issue: "Service failed to install"
**Fix**:
1. Close PowerShell
2. Right-click PowerShell → "Run as Administrator"
3. Re-run setup script

### Issue: Runner shows "Offline"
**Fix**:
```powershell
# Restart service
Restart-Service -Name "actions.runner.*"

# Or check logs for errors
Get-Content C:\actions-runner\_diag\Runner_*.log -Tail 50
```

### Issue: "Token invalid or expired"
**Fix**:
1. Get new token from GitHub
2. Re-run setup script with new token

### Issue: Build fails with "Unity license"
**Fix**:
1. Open Unity Hub on Windows PC
2. Sign in with your Unity account
3. Activate license (Personal/Plus/Pro)
4. Retry build

---

## 📞 Need More Help?

### Quick Reference
- **5-min guide**: `QUICK_START.md`
- **Full guide**: `SELF_HOSTED_RUNNER_SETUP.md`
- **Summary**: `IMPLEMENTATION_SUMMARY.md`

### Check Logs
```powershell
# Runner logs
Get-Content C:\actions-runner\_diag\Runner_*.log -Tail 50

# Build logs (during build)
Get-Content C:\actions-runner\_diag\Worker_*.log -Tail 100 -Wait

# Unity logs (after build)
Get-Content C:\actions-runner\_work\ineuj\ineuj\Logs\Editor.log -Tail 100
```

### GitHub Resources
- Runner settings: https://github.com/boardible/ineuj/settings/actions/runners
- Actions history: https://github.com/boardible/ineuj/actions
- Docs: https://docs.github.com/en/actions/hosting-your-own-runners

---

## 💰 Cost Tracking

Track your savings!

### Before Self-Hosted
- iOS build: $4.80 × 10/month = **$48**
- Android build: $5.60 × 10/month = **$56**
- **Total**: **$104/month**

### After Self-Hosted
- iOS build: $4.80 × 10/month = **$48**
- Android build: $0 × ∞/month = **$0**
- **Total**: **$48/month**

### Savings
- **Monthly**: $56 saved (54% reduction)
- **Annual**: $672 saved
- **ROI**: Immediate (first build)

---

## 📅 Maintenance Schedule

### Daily
- [ ] (Optional) Check runner status in GitHub

### Weekly
- [ ] Verify Windows PC has free disk space (>10GB)
- [ ] Check that service is running

### Monthly
- [ ] Review build success rate
- [ ] Clear old build logs if needed:
  ```powershell
  # Clean logs older than 30 days
  Get-ChildItem C:\actions-runner\_diag\*.log | 
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | 
    Remove-Item
  ```

### When Windows Updates
- [ ] Reboot PC
- [ ] Verify service auto-started:
  ```powershell
  Get-Service -Name "actions.runner.*"
  ```

---

## 🎉 Completion Checklist

**You're done when**:

- [x] Runner online in GitHub ✅
- [x] Service auto-starts ✅
- [x] Test build successful ✅
- [x] No GitHub charges for Android ✅
- [x] Workflow file updated ✅
- [x] Documentation read ✅
- [x] $40-56/month saved ✅

---

**Date Completed**: ________________

**Runner Name**: ________________

**First Successful Build**: ________________

**Notes**:
_________________________________________________________________

_________________________________________________________________

_________________________________________________________________

---

## 🚀 Next Steps After Setup

1. Monitor first 5 builds for any issues
2. Consider setting up remote access (TeamViewer/AnyDesk) for monitoring
3. Add PC to UPS if power stability is a concern
4. Document any PC-specific tweaks needed
5. Celebrate your cost savings! 🎊

---

**Keep this checklist for future reference or when setting up additional runners.**

**Last updated**: $(date)

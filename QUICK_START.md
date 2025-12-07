# Self-Hosted Runner - Quick Start Guide

## 🚀 5-Minute Setup

### Prerequisites
- ✅ Windows PC with Unity 6000.2.6f2 + Android Build Support
- ✅ Administrator access
- ✅ Internet connection

---

## Step 1: Get GitHub Token (2 minutes)

1. Open: https://github.com/boardible/ineuj/settings/actions/runners/new
2. Select **Windows** + **x64**
3. Copy the token from "Configure" section (looks like `A23XYZ...`)

---

## Step 2: Run Setup Script (3 minutes)

### On Your Windows PC:

```powershell
# Open PowerShell as Administrator (Win+X → "Windows PowerShell (Admin)")

# Navigate to project
cd C:\Dev\ineuj\Scripts

# Run setup (replace YOUR_TOKEN with actual token)
.\setupSelfHostedRunner-Windows.ps1 -GitHubToken "YOUR_TOKEN"
```

**That's it!** The script handles everything automatically.

---

## Step 3: Verify (30 seconds)

1. Check GitHub: https://github.com/boardible/ineuj/settings/actions/runners
2. Look for your runner with **green "Idle" status**

---

## Step 4: Update Workflow (1 minute)

Edit `.github/workflows/main.yml`:

**Line 185** - Change from:
```yaml
runs-on: macos-latest
```

To:
```yaml
runs-on: [self-hosted, windows, android]
```

**Line 36** - Change from:
```yaml
UNITY_VERSION: "6000.2.14f1"
```

To:
```yaml
UNITY_VERSION: "6000.2.6f2"
```

Commit and push:
```bash
git add .github/workflows/main.yml
git commit -m "Use self-hosted runner for Android"
git push origin main
```

---

## Test It!

```bash
# Trigger Android build
git push origin androidBuild
```

Watch it run on your PC for **$0** instead of **$5.60**! 🎉

---

## Troubleshooting

### "Script execution disabled"
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### "Unity not found"
- Install Unity 6000.2.6f2 via Unity Hub
- Ensure "Android Build Support" module is installed

### "Service failed to install"
- Reopen PowerShell as Administrator
- Re-run the script

### Runner shows "Offline"
```powershell
# Restart service
Get-Service -Name "actions.runner.*" | Restart-Service
```

---

## Cost Savings

| Build Type | Before | After | Savings |
|------------|--------|-------|---------|
| Android | $5.60/build | **$0** | 100% |
| iOS | $4.80/build | $4.80 | - |
| **Monthly** | **$88-128** | **$48-72** | **43%** |

---

## What Happens Next?

✅ Your Windows PC becomes a GitHub Actions runner  
✅ All Android builds run on your PC (free)  
✅ iOS builds still use GitHub (required for macOS)  
✅ Service auto-starts on Windows boot  
✅ Unlimited Android builds at no cost  

---

## Full Documentation

See `SELF_HOSTED_RUNNER_SETUP.md` for complete guide with:
- Detailed troubleshooting
- Security notes
- Maintenance procedures
- Alternative Linux/WSL setup

---

## Need Help?

1. Check logs: `C:\actions-runner\_diag\Runner_*.log`
2. View service: `Get-Service -Name "actions.runner.*"`
3. GitHub docs: https://docs.github.com/en/actions/hosting-your-own-runners

---

**You're saving $40-56/month! 🎊**

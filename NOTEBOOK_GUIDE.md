# 📓 Notebook Quick Guide - Self-Hosted Runner Setup

**For your Windows PC notebook - Just copy these commands!**

---

## 🎯 Goal
Turn this Windows PC into a free GitHub Actions runner for Android builds.  
**Saves $40-56/month** on CI/CD costs!

---

## ✅ Step 1: Check Unity (2 minutes)

Open PowerShell (regular, not admin):

```powershell
# Check if Unity is installed
Get-ChildItem "C:\Program Files\Unity\Hub\Editor" | Where-Object { $_.Name -eq "6000.2.6f2" }
```

**If nothing appears**: Install Unity 6000.2.6f2 via Unity Hub with Android Build Support

---

## 🔑 Step 2: Get GitHub Token (3 minutes)

### Option A: Automatic (Easiest)
```powershell
# Navigate to scripts
cd C:\Dev\ineuj\Scripts

# Run helper
.\getRunnerToken.ps1
```

Browser opens, follow instructions, copy token.

### Option B: Manual
1. Open: https://github.com/boardible/ineuj/settings/actions/runners/new
2. Select **Windows** + **x64**
3. Find `--token` in "Configure" section
4. Copy the long string after `--token`

---

## 🚀 Step 3: Run Setup (20 minutes)

**IMPORTANT**: Open PowerShell as **Administrator**
- Press `Win + X`
- Select "Windows PowerShell (Admin)"
- Click "Yes"

```powershell
# Navigate to scripts
cd C:\Dev\ineuj\Scripts

# Run setup (replace YOUR_TOKEN with actual token)
.\setupSelfHostedRunner-Windows.ps1 -GitHubToken "YOUR_TOKEN"
```

**Example**:
```powershell
.\setupSelfHostedRunner-Windows.ps1 -GitHubToken "A23XYZ4567ABCDEF890123HIJKLMN456789OPQRSTUV"
```

Wait for green "✓" messages. Script does everything automatically!

---

## ✅ Step 4: Verify (2 minutes)

### Check GitHub:
Open: https://github.com/boardible/ineuj/settings/actions/runners

Should see your PC with green **"Idle"** status

### Check Windows Service:
```powershell
Get-Service -Name "actions.runner.*"
```

Should show **"Running"**

---

## 🎉 Done!

Your PC is now a GitHub Actions runner!

**What happens next**:
- Android builds run on this PC (free)
- iOS builds run on GitHub (still paid, Apple requires macOS)
- Total savings: **$40-56/month** (43% reduction)

---

## 🆘 Problems?

### "Script won't run"
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### "Unity not found"
Install Unity Hub → Add 6000.2.6f2 → Android Build Support

### "Service failed"
Close PowerShell, reopen as Administrator

### Runner shows "Offline"
```powershell
Restart-Service -Name "actions.runner.*"
```

---

## 📚 Full Documentation

- **Quick Start**: `QUICK_START.md`
- **Full Guide**: `SELF_HOSTED_RUNNER_SETUP.md`
- **Checklist**: `SETUP_CHECKLIST.md`

---

## 💡 Key Points

✅ Script is fully automated  
✅ Creates Windows service (auto-starts on reboot)  
✅ Verifies Unity installation  
✅ Configures everything automatically  
✅ Safe and secure (GitHub-managed)  

⚠️ Token expires in a few hours (use quickly)  
⚠️ Must run as Administrator for service installation  
⚠️ PC needs stable internet connection  

---

**After setup, your PC will automatically handle all Android builds at $0 cost!** 🚀

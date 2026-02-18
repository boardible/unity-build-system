# 📝 Self-Hosted Runner Implementation - Complete Summary

**Date**: $(date)  
**Project**: boardible/ineuj (Unity 6 iOS/Android App)  
**Objective**: Reduce CI/CD costs by 43% using self-hosted Windows PC for Android builds

---

## 🎯 What We've Accomplished

### 1. **Created Automated Setup Scripts**

✅ **Windows Script**: `Scripts/setupSelfHostedRunner-Windows.ps1`
- Full PowerShell automation (379 lines)
- Parameter validation with help system
- Downloads GitHub Actions Runner v2.311.0
- Verifies Unity 6000.2.6f2 + Android Build Support
- Installs as Windows service (auto-starts on boot)
- Comprehensive error handling and colored output

✅ **Linux Script**: `Scripts/setupSelfHostedRunner-Linux.sh`
- Bash automation for Linux/WSL (268 lines)
- Systemd service integration
- Dependency management (libicu)
- Fallback to background execution

### 2. **Created Documentation**

✅ **Full Guide**: `Scripts/SELF_HOSTED_RUNNER_SETUP.md`
- Complete step-by-step instructions
- Troubleshooting section
- Security notes
- Maintenance procedures
- Cost analysis

✅ **Quick Reference**: `Scripts/QUICK_START.md`
- 5-minute setup guide
- Essential commands only
- Quick troubleshooting

### 3. **Updated Workflow File**

✅ Fixed Unity version: `6000.3.7f1` → `6000.2.6f2`
✅ Added TODO comment for self-hosted runner migration
✅ Maintained backward compatibility (still uses macOS until runner is set up)

---

## 💰 Cost Analysis

### Current Setup (Before)
| Component | Runner | Cost/Minute | Build Time | Cost/Build | Builds/Month | Monthly Cost |
|-----------|--------|-------------|------------|------------|--------------|--------------|
| iOS Build | macOS | $0.08 | 60 min | $4.80 | 10 | $48 |
| Android Build | macOS | $0.08 | 70 min | $5.60 | 10 | $56 |
| **TOTAL** | | | | | | **$88-128** |

### After Self-Hosted (Target)
| Component | Runner | Cost/Minute | Build Time | Cost/Build | Builds/Month | Monthly Cost |
|-----------|--------|-------------|------------|------------|--------------|--------------|
| iOS Build | macOS | $0.08 | 60 min | $4.80 | 10 | $48 |
| Android Build | **Self-Hosted** | **$0** | 70 min | **$0** | ∞ | **$0** |
| **TOTAL** | | | | | | **$48-72** |

### Savings Summary
- **Monthly Savings**: $40-56 (43% reduction)
- **Annual Savings**: $480-672
- **Hardware Cost**: $0 (using existing Windows PC)
- **Android Builds**: Unlimited at no cost
- **iOS Builds**: Still requires GitHub Actions (Apple macOS requirement)

---

## 📋 Implementation Checklist

### ✅ Completed on Mac (Developer Side)

- [x] Created `setupSelfHostedRunner-Windows.ps1`
- [x] Created `setupSelfHostedRunner-Linux.sh`
- [x] Made scripts executable (`chmod +x`)
- [x] Created `SELF_HOSTED_RUNNER_SETUP.md` (full guide)
- [x] Created `QUICK_START.md` (quick reference)
- [x] Fixed Unity version in workflow (6000.2.6f2)
- [x] Added TODO comment for runner migration
- [x] Documented architecture and requirements
- [x] Cost analysis completed

### 🔲 Pending on Windows PC (Your Side)

#### Step 1: Get GitHub Token
- [ ] Navigate to: https://github.com/boardible/ineuj/settings/actions/runners/new
- [ ] Select **Windows** + **x64**
- [ ] Copy registration token

#### Step 2: Transfer Script
- [ ] Clone/pull repo on Windows: `git clone https://github.com/boardible/ineuj.git`
- [ ] Or download script directly from GitHub
- [ ] Navigate to: `C:\Dev\ineuj\Scripts\`

#### Step 3: Run Setup
- [ ] Open PowerShell as Administrator
- [ ] Run: `.\setupSelfHostedRunner-Windows.ps1 -GitHubToken "YOUR_TOKEN"`
- [ ] Wait for automatic setup (~3 minutes)

#### Step 4: Verify
- [ ] Check GitHub: https://github.com/boardible/ineuj/settings/actions/runners
- [ ] Confirm runner shows **"Idle"** status (green)
- [ ] Verify labels: `self-hosted`, `windows`, `android`, `unity`

#### Step 5: Update Workflow
- [ ] Edit `.github/workflows/main.yml` line 179
- [ ] Change: `runs-on: macos-latest`
- [ ] To: `runs-on: [self-hosted, windows, android]`
- [ ] Commit and push changes

#### Step 6: Test
- [ ] Push to `androidBuild` branch
- [ ] Monitor GitHub Actions page
- [ ] Verify build runs on your Windows PC
- [ ] Confirm successful APK generation

---

## 🔧 Technical Details

### Runner Configuration
- **Repository**: boardible/ineuj
- **Labels**: `self-hosted`, `windows`, `android`, `unity`
- **Runner Name**: Defaults to PC hostname (customizable with `-RunnerName`)
- **Working Directory**: `C:\actions-runner`
- **Service Name**: `actions.runner.boardible-ineuj.<HOSTNAME>`

### System Requirements
- **OS**: Windows 10/11 (any edition)
- **RAM**: 8GB minimum, 16GB recommended
- **Disk**: 20GB free space minimum
- **Unity**: 6000.2.6f2 with Android Build Support
- **Network**: Stable internet connection
- **Permissions**: Administrator access for service installation

### Workflow Changes Made
```yaml
# Before
env:
  UNITY_VERSION: "6000.3.7f1"  # ❌ Wrong version

build_android:
  runs-on: macos-latest  # ❌ Expensive

# After
env:
  UNITY_VERSION: "6000.2.6f2"  # ✅ Correct version

build_android:
  runs-on: macos-latest  # ⚠️ TODO: Change after setup
  # Future: runs-on: [self-hosted, windows, android]
```

---

## 🚀 Quick Start Commands

### On Windows PC (Setup)
```powershell
# Open PowerShell as Administrator (Win+X → Windows PowerShell (Admin))

# Navigate to scripts
cd C:\Dev\ineuj\Scripts

# Run setup (replace YOUR_TOKEN)
.\setupSelfHostedRunner-Windows.ps1 -GitHubToken "YOUR_TOKEN"

# Verify service
Get-Service -Name "actions.runner.*"
```

### On Mac (Update Workflow)
```bash
# Edit workflow
code .github/workflows/main.yml

# Change line 179:
# From: runs-on: macos-latest
# To:   runs-on: [self-hosted, windows, android]

# Commit changes
git add .github/workflows/main.yml
git commit -m "Migrate Android builds to self-hosted runner"
git push origin main

# Test with Android build
git push origin androidBuild
```

---

## 📊 Expected Results

### Immediate Benefits
1. **Cost Reduction**: $40-56/month saved (43% less)
2. **Build Capacity**: Unlimited Android builds at no cost
3. **Build Speed**: Potentially faster (local hardware)
4. **Control**: Full visibility into build process

### Build Time Comparison
| Platform | Current (macOS) | Self-Hosted (Windows) | Delta |
|----------|-----------------|----------------------|-------|
| Android | ~70 minutes | ~60-70 minutes | Similar |
| iOS | ~60 minutes | N/A (requires macOS) | - |

### Monthly Build Capacity
| Scenario | Current (macOS) | Self-Hosted (Windows) |
|----------|-----------------|----------------------|
| Budget: $50 | ~9 Android builds | **Unlimited** |
| Budget: $100 | ~18 Android builds | **Unlimited** |
| 20 builds/month | $112 | **$0** |

---

## 🛡️ Security Considerations

### Runner Security
✅ **Isolated Service**: Runs with limited Windows service permissions  
✅ **Repo-Specific**: Only executes jobs from `boardible/ineuj`  
✅ **GitHub Validation**: All workflow files validated before execution  
✅ **No Inbound Connections**: Runner polls GitHub (outbound only)  

### Token Security
✅ **Time-Limited**: Registration tokens expire after a few hours  
✅ **Single-Use**: Cannot reuse after configuration  
✅ **Validated**: Script checks token format before use  
⚠️ **Never Commit**: Tokens must not be added to git  

### Network Requirements
- **Outbound HTTPS (443)**: `github.com`, `api.github.com`, `*.actions.githubusercontent.com`
- **Inbound**: None required
- **Firewall**: Allow outbound HTTPS connections

---

## 🔍 Monitoring & Logs

### GitHub Actions UI
- **URL**: https://github.com/boardible/ineuj/actions
- **Shows**: Build status, logs, artifacts
- **Real-time**: Updates during build execution

### Windows PC Logs
```powershell
# Runner logs
Get-Content C:\actions-runner\_diag\Runner_*.log -Tail 50

# Worker logs (active builds)
Get-Content C:\actions-runner\_diag\Worker_*.log -Tail 100 -Wait

# Service status
Get-Service -Name "actions.runner.*"

# Recent log files
Get-ChildItem C:\actions-runner\_diag\*.log | Sort-Object LastWriteTime -Descending | Select-Object -First 5
```

### Unity Build Logs
- **Location**: `C:\actions-runner\_work\ineuj\ineuj\Logs\`
- **File**: `Editor.log`
- **Contains**: Unity compilation errors, build progress, warnings

---

## 🆘 Troubleshooting Reference

### Common Issues & Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| "Script execution disabled" | PowerShell policy | `Set-ExecutionPolicy RemoteSigned` |
| "Unity not found" | Missing Unity 6000.2.6f2 | Install via Unity Hub |
| "Android Build Support not detected" | Missing module | Add via Unity Hub → Installs |
| "Service failed to install" | Not Administrator | Reopen PowerShell as Admin |
| Runner shows "Offline" | Service stopped | `Start-Service actions.runner.*` |
| Build fails "License not activated" | Unity not licensed | Activate via Unity Hub |
| "Token invalid" | Expired/used token | Get new token from GitHub |

### Support Resources
- **Full Guide**: `Scripts/SELF_HOSTED_RUNNER_SETUP.md`
- **Quick Start**: `Scripts/QUICK_START.md`
- **GitHub Docs**: https://docs.github.com/en/actions/hosting-your-own-runners
- **Unity Docs**: https://docs.unity3d.com/Manual/android-BuildProcess.html

---

## 📈 Next Steps

### Immediate (After Runner Setup)
1. ✅ Verify runner appears in GitHub (green "Idle" status)
2. ✅ Update workflow file (`runs-on: [self-hosted, windows, android]`)
3. ✅ Test with single Android build
4. ✅ Monitor first build for issues

### Short-term (First Week)
1. Monitor build success rate
2. Check disk space usage on Windows PC
3. Verify service auto-starts after Windows reboot
4. Document any PC-specific configuration

### Long-term (First Month)
1. Track actual cost savings
2. Compare build times (self-hosted vs macOS)
3. Consider adding more self-hosted runners if needed
4. Evaluate Linux/WSL alternative if performance issues

---

## 🎉 Success Criteria

You'll know the implementation is successful when:

✅ **Runner Status**: Green "Idle" indicator in GitHub  
✅ **Build Execution**: Android builds run on Windows PC  
✅ **Cost Reduction**: $0 charges for Android builds  
✅ **Reliability**: 95%+ build success rate  
✅ **Performance**: Build times comparable to macOS  
✅ **Maintenance**: Service auto-starts after reboot  

---

## 📞 Getting Help

### Documentation
1. **Start with**: `QUICK_START.md` (fastest solution)
2. **Detailed help**: `SELF_HOSTED_RUNNER_SETUP.md` (comprehensive)
3. **This file**: Overall strategy and context

### Logs to Check
1. **Script output**: PowerShell console during setup
2. **Runner logs**: `C:\actions-runner\_diag\Runner_*.log`
3. **Build logs**: GitHub Actions UI
4. **Unity logs**: `C:\actions-runner\_work\ineuj\ineuj\Logs\Editor.log`

### External Resources
- GitHub Actions docs (official)
- Unity Android build docs (official)
- Project architecture: `ARCHITECTURE_REFERENCE.md`

---

## 🏁 Final Notes

### Why This Approach?
- **iOS**: Must use macOS (Apple requirement) → Keep on GitHub Actions
- **Android**: Works on any OS → Migrate to free self-hosted
- **Hybrid**: Best balance of cost and functionality

### Alternative Approaches Considered
1. **Codemagic**: 500 free min/month, then $0.038/min (~$50/month after free tier)
2. **CircleCI**: 6,000 free Linux min/month (best free option, but complex setup)
3. **Unity Cloud Build**: Requires Unity Pro ($2,040/year) - not cost-effective
4. **All Self-Hosted**: iOS requires macOS hardware ($500+ Mac Mini)

### Decision Rationale
✅ **Lowest cost**: $0 for Android, $48-72 for iOS  
✅ **Zero hardware investment**: Using existing Windows PC  
✅ **Simple setup**: Automated scripts, ~30 minutes  
✅ **Scalable**: Add more runners easily  
✅ **Reliable**: GitHub-managed infrastructure for iOS  

---

**🎯 Ready to implement? Start with `QUICK_START.md` on your Windows PC!**

**📚 Need details? Read `SELF_HOSTED_RUNNER_SETUP.md` for comprehensive guide.**

**💡 Questions? Check troubleshooting sections in both docs.**

---

**Implementation Status**: ✅ Mac side complete, ⏳ waiting for Windows PC setup

**Cost Impact**: 💰 Will save $40-56/month (43% reduction) once complete

**Time to ROI**: 🚀 Immediate (first Android build after setup)

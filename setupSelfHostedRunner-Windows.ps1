# Self-Hosted GitHub Actions Runner Setup for Windows (Android Builds Only)
# This script sets up your Windows PC as a GitHub Actions runner for Unity Android builds

param(
    [string]$GitHubToken = "",
    [string]$RunnerName = "ineuj-windows-android",
    [switch]$SkipUnityCheck = $false,
    [switch]$Help = $false
)

# Script configuration
$ErrorActionPreference = "Stop"
$RepoOwner = "boardible"
$RepoName = "ineuj"
$UnityVersion = "6000.2.6f2"
$RunnerVersion = "2.311.0"

# Colors for output
function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Info { Write-Host $args -ForegroundColor Cyan }
function Write-Warning { Write-Host $args -ForegroundColor Yellow }
function Write-Error { Write-Host $args -ForegroundColor Red }

# Show help
if ($Help) {
    Write-Host @"
GitHub Actions Self-Hosted Runner Setup for Windows (Android Only)
===================================================================

This script will:
1. Download and install GitHub Actions runner software
2. Configure it to listen for Android build jobs
3. Verify Unity installation for Android builds
4. Set up as a Windows service (optional)

Usage:
    .\setupSelfHostedRunner-Windows.ps1 [-GitHubToken TOKEN] [-RunnerName NAME] [-SkipUnityCheck]

Parameters:
    -GitHubToken     Your GitHub runner registration token (required)
    -RunnerName      Name for this runner (default: ineuj-windows-android)
    -SkipUnityCheck  Skip Unity installation verification
    -Help            Show this help message

Getting a GitHub Token:
    1. Go to: https://github.com/$RepoOwner/$RepoName/settings/actions/runners/new
    2. Click "New self-hosted runner"
    3. Select "Windows" and "x64"
    4. Copy the token from the configuration command
    5. Run this script with: -GitHubToken "YOUR_TOKEN_HERE"

Example:
    .\setupSelfHostedRunner-Windows.ps1 -GitHubToken "ABCD1234EFGH5678"
"@
    exit 0
}

Write-Info "=============================================="
Write-Info "GitHub Actions Runner Setup - Android Builds"
Write-Info "=============================================="
Write-Host ""

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "This script should be run as Administrator for full functionality."
    Write-Warning "Service installation will be skipped if not running as admin."
    Write-Host ""
}

# Validate GitHub token
if ([string]::IsNullOrEmpty($GitHubToken)) {
    Write-Error "GitHub token is required!"
    Write-Host ""
    Write-Info "To get a token:"
    Write-Info "1. Visit: https://github.com/$RepoOwner/$RepoName/settings/actions/runners/new"
    Write-Info "2. Select 'Windows' platform"
    Write-Info "3. Copy the token from the config command"
    Write-Info "4. Run: .\setupSelfHostedRunner-Windows.ps1 -GitHubToken `"YOUR_TOKEN`""
    Write-Host ""
    exit 1
}

# Step 1: Create runner directory
Write-Info "[Step 1/7] Creating runner directory..."
$RunnerDir = "$env:USERPROFILE\actions-runner"
if (Test-Path $RunnerDir) {
    Write-Warning "Runner directory already exists: $RunnerDir"
    $response = Read-Host "Do you want to remove it and start fresh? (y/n)"
    if ($response -eq 'y') {
        Remove-Item -Path $RunnerDir -Recurse -Force
        Write-Success "Removed existing runner directory"
    } else {
        Write-Error "Aborted. Please remove the directory manually or use a different location."
        exit 1
    }
}
New-Item -ItemType Directory -Path $RunnerDir | Out-Null
Write-Success "Created runner directory: $RunnerDir"

# Step 2: Download GitHub Actions runner
Write-Info "[Step 2/7] Downloading GitHub Actions runner..."
Set-Location $RunnerDir
$RunnerUrl = "https://github.com/actions/runner/releases/download/v$RunnerVersion/actions-runner-win-x64-$RunnerVersion.zip"
$RunnerZip = "$RunnerDir\actions-runner.zip"

try {
    Invoke-WebRequest -Uri $RunnerUrl -OutFile $RunnerZip
    Write-Success "Downloaded runner software"
} catch {
    Write-Error "Failed to download runner: $_"
    exit 1
}

# Step 3: Extract runner
Write-Info "[Step 3/7] Extracting runner..."
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($RunnerZip, $RunnerDir)
    Remove-Item $RunnerZip
    Write-Success "Extracted runner software"
} catch {
    Write-Error "Failed to extract runner: $_"
    exit 1
}

# Step 4: Configure runner
Write-Info "[Step 4/7] Configuring runner for Android builds..."
try {
    $configArgs = @(
        "--url", "https://github.com/$RepoOwner/$RepoName",
        "--token", $GitHubToken,
        "--name", $RunnerName,
        "--labels", "self-hosted,windows,android,unity",
        "--work", "_work",
        "--unattended"
    )
    
    & "$RunnerDir\config.cmd" @configArgs
    Write-Success "Runner configured successfully"
} catch {
    Write-Error "Failed to configure runner: $_"
    exit 1
}

# Step 5: Verify Unity installation
if (-not $SkipUnityCheck) {
    Write-Info "[Step 5/7] Verifying Unity installation..."
    
    # Common Unity Hub installation paths
    $UnityHubPaths = @(
        "$env:ProgramFiles\Unity\Hub\Editor\$UnityVersion\Editor\Unity.exe",
        "${env:ProgramFiles(x86)}\Unity\Hub\Editor\$UnityVersion\Editor\Unity.exe",
        "$env:ProgramFiles\Unity\Editor\$UnityVersion\Editor\Unity.exe"
    )
    
    $UnityPath = $null
    foreach ($path in $UnityHubPaths) {
        if (Test-Path $path) {
            $UnityPath = $path
            break
        }
    }
    
    if ($UnityPath) {
        Write-Success "Found Unity $UnityVersion at: $UnityPath"
        
        # Check for Android Build Support
        $AndroidModulePath = Split-Path $UnityPath | Join-Path -ChildPath "Data\PlaybackEngines\AndroidPlayer"
        if (Test-Path $AndroidModulePath) {
            Write-Success "Android Build Support is installed"
        } else {
            Write-Warning "Android Build Support is NOT installed"
            Write-Warning "Install it via Unity Hub -> Installs -> $UnityVersion -> Add Modules -> Android Build Support"
        }
    } else {
        Write-Warning "Unity $UnityVersion not found in common locations"
        Write-Info "Please ensure Unity $UnityVersion is installed with Android Build Support"
        Write-Info "Download from: https://unity.com/releases/editor/archive"
    }
} else {
    Write-Info "[Step 5/7] Skipping Unity verification (as requested)"
}

# Step 6: Install as Windows Service (optional)
Write-Info "[Step 6/7] Installing as Windows Service..."
if ($isAdmin) {
    try {
        & "$RunnerDir\svc.cmd" install
        Write-Success "Installed runner as Windows service"
        Write-Info "The runner will start automatically on system boot"
    } catch {
        Write-Warning "Failed to install service (non-critical): $_"
        Write-Info "You can run the runner manually with: .\run.cmd"
    }
} else {
    Write-Warning "Not running as Administrator - skipping service installation"
    Write-Info "To install as service later, run as Admin: .\svc.cmd install"
}

# Step 7: Start the runner
Write-Info "[Step 7/7] Starting the runner..."
if ($isAdmin) {
    try {
        & "$RunnerDir\svc.cmd" start
        Write-Success "Runner service started"
    } catch {
        Write-Warning "Failed to start service. Starting manually..."
        Start-Process -FilePath "$RunnerDir\run.cmd" -NoNewWindow
    }
} else {
    Write-Info "Starting runner in current window..."
    Write-Info "Press Ctrl+C to stop the runner"
    Write-Host ""
    & "$RunnerDir\run.cmd"
}

# Final instructions
Write-Host ""
Write-Success "=============================================="
Write-Success "Runner Setup Complete!"
Write-Success "=============================================="
Write-Host ""
Write-Info "Your Windows PC is now configured as a GitHub Actions runner for Android builds."
Write-Host ""
Write-Info "Next Steps:"
Write-Info "1. Verify runner is online: https://github.com/$RepoOwner/$RepoName/settings/actions/runners"
Write-Info "2. Update your workflow file (.github/workflows/main.yml):"
Write-Info "   Change 'runs-on: macos-latest' to 'runs-on: self-hosted' for Android builds"
Write-Info "3. Push to androidBuild branch to trigger a test build"
Write-Host ""
Write-Info "Runner Location: $RunnerDir"
Write-Info "Runner Name: $RunnerName"
Write-Info "Labels: self-hosted, windows, android, unity"
Write-Host ""
Write-Info "To stop the runner:"
if ($isAdmin) {
    Write-Info "  .\svc.cmd stop"
} else {
    Write-Info "  Press Ctrl+C (if running in foreground)"
}
Write-Host ""
Write-Info "To uninstall the runner:"
Write-Info "  cd $RunnerDir"
Write-Info "  .\config.cmd remove --token YOUR_REMOVAL_TOKEN"
Write-Host ""

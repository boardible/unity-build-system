<#
.SYNOPSIS
    Helper script to open GitHub runner registration page and guide token retrieval.

.DESCRIPTION
    This script provides an interactive guide for obtaining a GitHub Actions runner
    registration token. It opens the correct GitHub page and walks you through the process.

.EXAMPLE
    .\getRunnerToken.ps1
    
    Opens GitHub runner registration page and displays instructions.

.NOTES
    This is a helper script for the self-hosted runner setup.
    After getting the token, use it with setupSelfHostedRunner-Windows.ps1
#>

[CmdletBinding()]
param()

function Write-ColorOutput {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('Green', 'Yellow', 'Red', 'Cyan', 'White')]
        [string]$Color = 'White'
    )
    
    Write-Host $Message -ForegroundColor $Color
}

function Show-Banner {
    Write-Host ""
    Write-ColorOutput "╔════════════════════════════════════════════════════════════════════╗" -Color Cyan
    Write-ColorOutput "║     GitHub Actions Runner - Token Retrieval Helper                ║" -Color Cyan
    Write-ColorOutput "║     Project: boardible/ineuj                                       ║" -Color Cyan
    Write-ColorOutput "╚════════════════════════════════════════════════════════════════════╝" -Color Cyan
    Write-Host ""
}

function Open-GitHubRunnerPage {
    $url = "https://github.com/boardible/ineuj/settings/actions/runners/new"
    
    Write-ColorOutput "Opening GitHub runner registration page..." -Color Cyan
    Write-Host ""
    
    try {
        Start-Process $url
        Write-ColorOutput "✓ Browser opened successfully" -Color Green
    }
    catch {
        Write-ColorOutput "✗ Could not open browser automatically" -Color Yellow
        Write-ColorOutput "  Please manually open this URL:" -Color Yellow
        Write-Host ""
        Write-ColorOutput "  $url" -Color White
    }
    
    Write-Host ""
}

function Show-Instructions {
    Write-ColorOutput "═══════════════════════════════════════════════════════════════════" -Color Cyan
    Write-ColorOutput "  STEP-BY-STEP INSTRUCTIONS" -Color Cyan
    Write-ColorOutput "═══════════════════════════════════════════════════════════════════" -Color Cyan
    Write-Host ""
    
    Write-ColorOutput "Step 1: Select Platform" -Color Yellow
    Write-Host "  • Choose: Windows" -ForegroundColor White
    Write-Host "  • Choose: x64" -ForegroundColor White
    Write-Host ""
    
    Write-ColorOutput "Step 2: Find the 'Configure' Section" -Color Yellow
    Write-Host "  • Scroll down on the page" -ForegroundColor White
    Write-Host "  • Look for a code block with commands" -ForegroundColor White
    Write-Host ""
    
    Write-ColorOutput "Step 3: Locate the Token" -Color Yellow
    Write-Host "  • Find the line that starts with: ./config.cmd" -ForegroundColor White
    Write-Host "  • Look for the parameter: --token" -ForegroundColor White
    Write-Host "  • The token looks like this:" -ForegroundColor White
    Write-Host ""
    Write-ColorOutput "    --token A23XYZ4567ABCDEF890123HIJKLMN456789OPQRSTUV..." -Color Green
    Write-Host ""
    
    Write-ColorOutput "Step 4: Copy ONLY the Token Value" -Color Yellow
    Write-Host "  • Do NOT copy '--token'" -ForegroundColor White
    Write-Host "  • Copy ONLY the long alphanumeric string after --token" -ForegroundColor White
    Write-Host "  • The token is usually 60-80 characters long" -ForegroundColor White
    Write-Host ""
    
    Write-ColorOutput "═══════════════════════════════════════════════════════════════════" -Color Cyan
    Write-Host ""
}

function Show-TokenInfo {
    Write-ColorOutput "📋 IMPORTANT TOKEN INFORMATION" -Color Yellow
    Write-Host ""
    Write-Host "  • Tokens EXPIRE after a few hours (use quickly)" -ForegroundColor White
    Write-Host "  • Tokens are SINGLE-USE (cannot reuse after setup)" -ForegroundColor White
    Write-Host "  • Do NOT commit tokens to git" -ForegroundColor White
    Write-Host "  • Keep token private (anyone with it can register runners)" -ForegroundColor White
    Write-Host ""
}

function Show-NextSteps {
    Write-ColorOutput "═══════════════════════════════════════════════════════════════════" -Color Cyan
    Write-ColorOutput "  NEXT STEPS - After Getting Token" -Color Cyan
    Write-ColorOutput "═══════════════════════════════════════════════════════════════════" -Color Cyan
    Write-Host ""
    
    Write-ColorOutput "1. Copy the token from GitHub" -Color Yellow
    Write-Host ""
    
    Write-ColorOutput "2. Open PowerShell as Administrator" -Color Yellow
    Write-Host "   • Press Win+X" -ForegroundColor White
    Write-Host "   • Select 'Windows PowerShell (Admin)'" -ForegroundColor White
    Write-Host ""
    
    Write-ColorOutput "3. Navigate to scripts folder" -Color Yellow
    Write-Host "   cd C:\Dev\ineuj\Scripts" -ForegroundColor Cyan
    Write-Host ""
    
    Write-ColorOutput "4. Run the setup script with your token" -Color Yellow
    Write-Host '   .\setupSelfHostedRunner-Windows.ps1 -GitHubToken "YOUR_TOKEN_HERE"' -ForegroundColor Cyan
    Write-Host ""
    
    Write-ColorOutput "   Example:" -Color White
    Write-Host '   .\setupSelfHostedRunner-Windows.ps1 -GitHubToken "A23XYZ456..."' -ForegroundColor Green
    Write-Host ""
    
    Write-ColorOutput "═══════════════════════════════════════════════════════════════════" -Color Cyan
    Write-Host ""
}

function Wait-ForUser {
    Write-ColorOutput "Press any key to continue (after copying the token)..." -Color Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Write-Host ""
}

function Test-TokenFormat {
    Write-ColorOutput "Would you like to validate your token format? (Y/N)" -Color Yellow
    $response = Read-Host
    
    if ($response -eq 'Y' -or $response -eq 'y') {
        Write-Host ""
        Write-ColorOutput "Paste your token (it will be hidden):" -Color Cyan
        $secureToken = Read-Host -AsSecureString
        $token = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
        )
        
        Write-Host ""
        
        if ($token -match '^[A-Z0-9]{60,}$') {
            Write-ColorOutput "✓ Token format looks correct!" -Color Green
            Write-Host ""
            Write-ColorOutput "Token length: $($token.Length) characters" -Color Cyan
            Write-Host ""
            Write-ColorOutput "Ready to use! Run this command:" -Color Green
            Write-Host ""
            Write-ColorOutput '.\setupSelfHostedRunner-Windows.ps1 -GitHubToken "' -Color Cyan -NoNewline
            Write-ColorOutput "$token" -Color White -NoNewline
            Write-ColorOutput '"' -Color Cyan
            Write-Host ""
        }
        else {
            Write-ColorOutput "⚠ Token format doesn't look right" -Color Yellow
            Write-Host ""
            Write-Host "  Expected: Long alphanumeric string (60+ characters)" -ForegroundColor White
            Write-Host "  Got: $($token.Length) characters" -ForegroundColor White
            Write-Host ""
            Write-ColorOutput "  Common mistakes:" -Color Yellow
            Write-Host "    • Including '--token' in the copied text" -ForegroundColor White
            Write-Host "    • Including quotes around the token" -ForegroundColor White
            Write-Host "    • Copying only part of the token" -ForegroundColor White
            Write-Host "    • Extra spaces before/after the token" -ForegroundColor White
            Write-Host ""
            Write-ColorOutput "  Try copying the token again from GitHub" -Color Cyan
        }
        Write-Host ""
    }
}

# Main execution
Clear-Host
Show-Banner
Show-Instructions
Show-TokenInfo
Open-GitHubRunnerPage
Wait-ForUser
Show-NextSteps
Test-TokenFormat

Write-ColorOutput "════════════════════════════════════════════════════════════════════" -Color Cyan
Write-ColorOutput "  Need help? See: SELF_HOSTED_RUNNER_SETUP.md" -Color Cyan
Write-ColorOutput "  Quick start: QUICK_START.md" -Color Cyan
Write-ColorOutput "════════════════════════════════════════════════════════════════════" -Color Cyan
Write-Host ""
Write-ColorOutput "Good luck! 🚀" -Color Green
Write-Host ""

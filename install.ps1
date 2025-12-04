<#
.SYNOPSIS
    Bulk Installation and Update Script using Winget.

.DESCRIPTION
    Reads packages from packages.txt.
    Scans the system for current state (installed/upgradable).
    Installs missing packages and updates outdated ones.
#>

# --- Configuration ---
$PackageFile = Join-Path $PSScriptRoot "packages.txt"
$WingetArgs = "--accept-package-agreements --accept-source-agreements --silent --disable-interactivity"

# --- Helper Functions ---

function Show-Header {
    Clear-Host
    $header = @'
 ____    _ __   _____ __  __ ____  _    _ ____       _    _  ___ ____  
/ ___|  / \\ \ / /_ _|  \/  | __ )| | | |  _ \    / \  | |/ ( ) ___| 
\___ \ / _ \\ V / | || |\/| |  _ \| | | | |_) |  / _ \ | ' /|/\___ \ 
 ___) / ___ \| |  | || |  | | |_) | |_| |  _ <  / ___ \| . \   ___) |
|____/_/  _\_\_|_|___|_|__|_|____/_\___/|_| \_\/_/   \_\_|\_\ |____/ 
\ \       / /_ _| \ | / ___|| ____|_    _|                       
 \ \ /\ / / | ||  \| \___ \|  _|   | |                           
  \ V  V /  | || |\  |___) | |___  | |                           
   \_/\_/  |___|_| \_|____/|_____| |_|                           
'@
    Write-Host $header -ForegroundColor Cyan
    Write-Host "`nWelcome to the Automated Installation Wizard." -ForegroundColor White
    Write-Host "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor DarkGray
    Write-Host "--------------------------------------------------------`n" -ForegroundColor DarkGray
}

function Get-PackageList {
    if (-not (Test-Path $PackageFile)) {
        Write-Host "[ERROR] $PackageFile not found!" -ForegroundColor Red
        exit 1
    }
    return Get-Content $PackageFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -notmatch "^#" }
}

function Scan-System {
    Write-Host "[SCANNING] Analyzing system state (this may take a few seconds)..." -ForegroundColor Yellow
    
    # Batch scan to avoid multiple expensive calls
    $installedRaw = winget list 2>&1
    $upgradableRaw = winget upgrade 2>&1
    
    return @{
        Installed = $installedRaw | Out-String
        Upgradable = $upgradableRaw | Out-String
    }
}

function Install-Or-Update {
    param (
        [string]$PackageId,
        [hashtable]$SystemState
    )

    # Check state
    $isInstalled = $SystemState.Installed -match $PackageId
    $needsUpdate = $SystemState.Upgradable -match $PackageId

    if (-not $isInstalled) {
        Write-Host "[INSTALLING] $PackageId not found. Installing..." -ForegroundColor Cyan
        Start-Process winget -ArgumentList "install --id $PackageId $WingetArgs" -Wait -NoNewWindow
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] $PackageId installed successfully." -ForegroundColor Green
        } else {
            Write-Host "  [ERROR] Failed to install $PackageId. Exit code: $LASTEXITCODE" -ForegroundColor Red
        }
    }
    elseif ($needsUpdate) {
        Write-Host "[UPDATING] Update available for $PackageId. Updating..." -ForegroundColor Magenta
        Start-Process winget -ArgumentList "upgrade --id $PackageId $WingetArgs" -Wait -NoNewWindow
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] $PackageId updated successfully." -ForegroundColor Green
        } else {
            Write-Host "  [ERROR] Failed to update $PackageId." -ForegroundColor Red
        }
    }
    else {
        Write-Host "[SKIPPED] $PackageId is up to date." -ForegroundColor DarkGray
    }
}

# --- Main Execution ---

Show-Header

# 1. Read package list
$targetPackages = Get-PackageList
Write-Host "[INFO] Processing $($targetPackages.Count) packages.`n" -ForegroundColor Gray

# 2. Scan System
$systemState = Scan-System

Write-Host "`n[PROCESS] Starting package operations...`n" -ForegroundColor White

# 3. Apply Operations
foreach ($pkg in $targetPackages) {
    Install-Or-Update -PackageId $pkg.Trim() -SystemState $systemState
}

Write-Host "`n--------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "[COMPLETED] All operations finished." -ForegroundColor Green
Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

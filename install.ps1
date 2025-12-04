<#
.SYNOPSIS
    Bulk Installation and Update Script with Process Management.

.DESCRIPTION
    Parses packages.txt (Format: PackageId=ProcessName).
    Terminates conflicting processes before updating.
    Installs missing packages and updates outdated ones.
#>

# --- Configuration ---
$PackageFile = Join-Path $PSScriptRoot "packages.txt"
$WingetArgs = "--accept-package-agreements --accept-source-agreements --silent --disable-interactivity"

# --- Helper Functions ---

function Show-Header {
    Clear-Host
    $header = @'
 ____    _ __   _____ __  __ ____  _   _ ____      _    _  ___ ____  
/ ___|  / \\ \ / /_ _|  \/  | __ )| | | |  _ \    / \  | |/ ( ) ___| 
\___ \ / _ \\ V / | || |\/| |  _ \| | | | |_) |  / _ \ | ' /|/\___ \ 
 ___) / ___ \| |  | || |  | | |_) | |_| |  _ <  / ___ \| . \   ___) |
|____/_/  _\_\_|_|___|_|__|_|____/_\___/|_| \_\/_/   \_\_|\_\ |____/ 
\ \      / /_ _| \ | / ___|| ____|_    _|                       
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
    
    $rawLines = Get-Content $PackageFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -notmatch "^#" }
    $parsedPackages = @()

    foreach ($line in $rawLines) {
        $parts = $line.Split('=')
        $pkgId = $parts[0].Trim()
        $procName = if ($parts.Count -gt 1) { $parts[1].Trim() } else { $null }

        $parsedPackages += [PSCustomObject]@{
            Id = $pkgId
            ProcessName = $procName
        }
    }
    return $parsedPackages
}

function Scan-System {
    Write-Host "[SCANNING] Analyzing system state..." -ForegroundColor Yellow
    
    # Batch scan optimizes performance
    $installedRaw = winget list 2>&1
    $upgradableRaw = winget upgrade 2>&1
    
    return @{
        Installed = $installedRaw | Out-String
        Upgradable = $upgradableRaw | Out-String
    }
}

function Terminate-Process {
    param ([string]$ProcessName)
    
    if ([string]::IsNullOrWhiteSpace($ProcessName)) { return }

    $runningProcess = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if ($runningProcess) {
        Write-Host "  [PROCESS] Closing '$ProcessName' to prevent conflicts..." -ForegroundColor Yellow
        Stop-Process -Name $ProcessName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2 # Grace period for file release
    }
}

function Install-Or-Update {
    param (
        [Parameter(Mandatory)]$PackageInfo,
        [hashtable]$SystemState
    )

    $id = $PackageInfo.Id
    $proc = $PackageInfo.ProcessName

    $isInstalled = $SystemState.Installed -match $id
    $needsUpdate = $SystemState.Upgradable -match $id

    if (-not $isInstalled) {
        Write-Host "[INSTALLING] $id not found. Installing..." -ForegroundColor Cyan
        Start-Process winget -ArgumentList "install --id $id $WingetArgs" -Wait -NoNewWindow
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] Success." -ForegroundColor Green
        } else {
            Write-Host "  [ERROR] Installation failed. Code: $LASTEXITCODE" -ForegroundColor Red
        }
    }
    elseif ($needsUpdate) {
        Write-Host "[UPDATING] Update available for $id." -ForegroundColor Magenta
        
        # Kill process before update
        Terminate-Process -ProcessName $proc

        Start-Process winget -ArgumentList "upgrade --id $id $WingetArgs" -Wait -NoNewWindow
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] Update successful." -ForegroundColor Green
        } else {
            Write-Host "  [ERROR] Update failed." -ForegroundColor Red
        }
    }
    else {
        Write-Host "[SKIPPED] $id is up to date." -ForegroundColor DarkGray
    }
}

# --- Main Execution ---

Show-Header

# 1. Parse packages
$targetPackages = Get-PackageList
Write-Host "[INFO] Processing $($targetPackages.Count) packages.`n" -ForegroundColor Gray

# 2. System Scan
$systemState = Scan-System

Write-Host "`n[PROCESS] Starting operations...`n" -ForegroundColor White

# 3. Execution Loop
foreach ($pkg in $targetPackages) {
    Install-Or-Update -PackageInfo $pkg -SystemState $systemState
}

Write-Host "`n--------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "[COMPLETED] Operations finished." -ForegroundColor Green
Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

<#
.SYNOPSIS
    Automated software installation script with Pre-Flight Analysis.

.DESCRIPTION
    1. Analyzes the current system state (Bulk check).
    2. Identifies missing or outdated packages from 'packages.txt'.
    3. Displays a summary plan.
    4. Executes installations/upgrades only where necessary.

.NOTES
    File Name      : install_apps.ps1
    Config File    : packages.txt
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Configuration path
$ConfigFileName = "packages.txt"
$ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath $ConfigFileName

# Custom Objects for Status Tracking
$Status = @{
    Missing    = "Missing (Will Install)"
    Outdated   = "Outdated (Will Upgrade)"
    UpToDate   = "Up to Date (Skipping)"
}

<#
.FUNCTION Show-Banner
#>
function Show-Banner {
    Clear-Host
    $Banner = @"
 ____    _ __   _____ __  __ ____  _    _ ____       _    _  ___ ____  
/ ___|  / \\ \ / /_ _|  \/  | __ )| | | |  _ \    / \  | |/ ( ) ___| 
\___ \ / _ \\ V / | || |\/| |  _ \| | | | |_) |  / _ \ | ' /|/\___ \ 
 ___) / ___ \| |  | || |  | | |_) | |_| |  _ <  / ___ \| . \   ___) |
|____/_/  _\_\_|_|___|_|__|_|____/_\___/|_| \_\/_/    \_\_|\_\ |____/ 
\ \       / /_ _| \ | / ___|| ____|_    _|                            
 \ \ /\ / / | ||  \| \___ \|  _|   | |                                
  \ V  V /  | || |\  |___) | |___  | |                                
   \_/\_/  |___|_| \_|____/|_____| |_|
"@
    Write-Host $Banner -ForegroundColor Cyan
}

<#
.FUNCTION Get-PackageList
#>
function Get-PackageList {
    param ( [string]$Path )
    if (-not (Test-Path -Path $Path)) { throw "Configuration file not found at: $Path" }
    
    return Get-Content -Path $Path | 
           ForEach-Object { $_.Trim() } | 
           Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith("#") }
}

<#
.FUNCTION Get-SystemState
.DESCRIPTION
    Fetches all installed and upgradeable packages in one go to avoid slow iterations.
#>
function Get-SystemState {
    Write-Host " [1/3] Fetching installed packages list..." -ForegroundColor Yellow
    # We capture the raw string output of all installed apps
    $Global:InstalledData = winget list --source winget 2>&1 | Out-String

    Write-Host " [2/3] Checking for available upgrades..." -ForegroundColor Yellow
    # We capture the raw string output of all available upgrades
    $Global:UpgradeData = winget upgrade --source winget --include-unknown 2>&1 | Out-String
}

<#
.FUNCTION Analyze-Packages
.DESCRIPTION
    Compares the target list against the system state.
#>
function Analyze-Packages {
    param ( [string[]]$TargetPackages )
    
    $ActionPlan = @()

    Write-Host " [3/3] Analyzing package status..." -ForegroundColor Yellow

    foreach ($Pkg in $TargetPackages) {
        $CurrentStatus = $null

        # Check Logic: String matching is faster and reliable enough for IDs
        if ($Global:InstalledData -match "\b$([Regex]::Escape($Pkg))\b") {
            if ($Global:UpgradeData -match "\b$([Regex]::Escape($Pkg))\b") {
                $CurrentStatus = $Status.Outdated
            } else {
                $CurrentStatus = $Status.UpToDate
            }
        } else {
            $CurrentStatus = $Status.Missing
        }

        $ActionPlan += [PSCustomObject]@{
            PackageId = $Pkg
            Status    = $CurrentStatus
        }
    }
    return $ActionPlan
}

<#
.FUNCTION Execute-Plan
.DESCRIPTION
    Executes the installation/upgrade commands based on the analysis.
#>
function Execute-Plan {
    param ( $Plan )

    # Filter only items that need action
    $ToProcess = $Plan | Where-Object { $_.Status -ne $Status.UpToDate }

    if ($ToProcess.Count -eq 0) {
        Write-Host "`nAll packages are already installed and up to date! Nothing to do." -ForegroundColor Green
        return
    }

    Write-Host "`nStarting Execution Phase ($($ToProcess.Count) tasks)..." -ForegroundColor Yellow
    Write-Host "--------------------------------------------------"

    foreach ($Item in $ToProcess) {
        $Pkg = $Item.PackageId
        Write-Host "Processing: $Pkg" -NoNewline

        try {
            if ($Item.Status -eq $Status.Missing) {
                Write-Host " [Installing]" -ForegroundColor Cyan
                winget install --id $Pkg -e --source winget --accept-package-agreements --accept-source-agreements --silent
            }
            elseif ($Item.Status -eq $Status.Outdated) {
                Write-Host " [Upgrading]" -ForegroundColor Magenta
                winget upgrade --id $Pkg -e --silent --accept-package-agreements --accept-source-agreements --include-unknown
            }
            Write-Host " -> Done." -ForegroundColor Green
        }
        catch {
            Write-Error "`nFailed to process $Pkg. Error: $_"
        }
    }
}

# --- Main Execution Block ---

try {
    Show-Banner

    # 1. Load Configuration
    $TargetList = Get-PackageList -Path $ConfigPath
    if ($null -eq $TargetList -or $TargetList.Count -eq 0) {
        Write-Warning "Package list is empty."
        exit
    }
    Write-Host "Loaded $($TargetList.Count) packages from config."

    # 2. Analyze System (Parallel-like bulk check)
    Get-SystemState
    $Plan = Analyze-Packages -TargetPackages $TargetList

    # 3. Show Summary Table
    Write-Host "`nAnalysis Complete. Summary:" -ForegroundColor White
    $Plan | Format-Table -AutoSize

    # 4. Execute
    Execute-Plan -Plan $Plan

    Write-Host "`nAll operations completed successfully." -ForegroundColor Green
}
catch {
    Write-Error "Critical Error: $_"
    exit 1
}

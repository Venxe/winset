<#
.SYNOPSIS
    Automated software installation script with Smart Process Management.

.DESCRIPTION
    1. Reads 'packages.txt' to get Package IDs and optional Process Names.
    2. Format in TXT: "PackageID=ProcessName" or just "PackageID".
    3. Analyzes system state (Parallel-like check).
    4. Kills conflicting processes defined in the TXT file before updating.
    5. Installs or upgrades packages efficiently.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Configuration path
$ConfigFileName = "packages.txt"
$ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath $ConfigFileName

# Status Enum
$Status = @{
    Missing    = "Missing (Will Install)"
    Outdated   = "Outdated (Will Upgrade)"
    UpToDate   = "Up to Date (Skipping)"
}

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
.FUNCTION Get-PackageConfig
.DESCRIPTION
    Parses the TXT file into a structured list of objects.
    Splits lines by '=' to separate ID and Process Name.
#>
function Get-PackageConfig {
    param ( [string]$Path )
    if (-not (Test-Path -Path $Path)) { throw "Configuration file not found at: $Path" }
    
    $RawContent = Get-Content -Path $Path
    $ConfigList = @()

    foreach ($Line in $RawContent) {
        $Trimmed = $Line.Trim()
        # Skip empty lines and comments
        if ([string]::IsNullOrWhiteSpace($Trimmed) -or $Trimmed.StartsWith("#")) { continue }

        # Parse "PackageID=ProcessName"
        if ($Trimmed -match "=") {
            $Parts = $Trimmed -split "=", 2
            $ConfigList += [PSCustomObject]@{
                Id          = $Parts[0].Trim()
                ProcessName = $Parts[1].Trim()
            }
        }
        else {
            # Case where no process name is provided
            $ConfigList += [PSCustomObject]@{
                Id          = $Trimmed
                ProcessName = $null
            }
        }
    }
    return $ConfigList
}

function Get-SystemState {
    Write-Host " [1/3] Fetching installed packages list..." -ForegroundColor Yellow
    $Global:InstalledData = winget list --source winget 2>&1 | Out-String

    Write-Host " [2/3] Checking for available upgrades..." -ForegroundColor Yellow
    $Global:UpgradeData = winget upgrade --source winget --include-unknown 2>&1 | Out-String
}

function Analyze-Packages {
    param ( $ConfigList )
    $ActionPlan = @()
    Write-Host " [3/3] Analyzing package status..." -ForegroundColor Yellow

    foreach ($Item in $ConfigList) {
        $PkgId = $Item.Id
        $CurrentStatus = $null

        if ($Global:InstalledData -match "\b$([Regex]::Escape($PkgId))\b") {
            if ($Global:UpgradeData -match "\b$([Regex]::Escape($PkgId))\b") {
                $CurrentStatus = $Status.Outdated
            } else {
                $CurrentStatus = $Status.UpToDate
            }
        } else {
            $CurrentStatus = $Status.Missing
        }

        # Add status to the existing object
        $Item | Add-Member -MemberType NoteProperty -Name "Status" -Value $CurrentStatus
        $ActionPlan += $Item
    }
    return $ActionPlan
}

function Stop-ConflictingProcess {
    param ( [string]$ProcessName )

    if (-not [string]::IsNullOrWhiteSpace($ProcessName)) {
        $RunningProc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue

        if ($RunningProc) {
            Write-Host "    ! Closing running instance of '$ProcessName'..." -ForegroundColor DarkYellow
            try {
                Stop-Process -Name $ProcessName -Force -ErrorAction Stop
                Start-Sleep -Seconds 2
            }
            catch {
                Write-Warning "    Could not close $ProcessName. Install might fail."
            }
        }
    }
}

function Execute-Plan {
    param ( $Plan )
    $ToProcess = $Plan | Where-Object { $_.Status -ne $Status.UpToDate }

    if ($ToProcess.Count -eq 0) {
        Write-Host "`nAll packages are already installed and up to date! Nothing to do." -ForegroundColor Green
        return
    }

    Write-Host "`nStarting Execution Phase ($($ToProcess.Count) tasks)..." -ForegroundColor Yellow
    Write-Host "--------------------------------------------------"

    foreach ($Item in $ToProcess) {
        $Pkg = $Item.Id
        Write-Host "Processing: $Pkg" -NoNewline

        # Kill App using the name from the TXT file
        Stop-ConflictingProcess -ProcessName $Item.ProcessName

        try {
            if ($Item.Status -eq $Status.Missing) {
                Write-Host " [Installing]" -ForegroundColor Cyan
                winget install --id $Pkg -e --source winget --accept-package-agreements --accept-source-agreements --silent
            }
            elseif ($Item.Status -eq $Status.Outdated) {
                Write-Host " [Upgrading]" -ForegroundColor Magenta
                winget upgrade --id $Pkg -e --silent --accept-package-agreements --accept-source-agreements --include-unknown --force
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
    
    # 1. Load Config (Parses ID=ProcessName)
    $TargetConfig = Get-PackageConfig -Path $ConfigPath
    
    if ($TargetConfig.Count -eq 0) {
        Write-Warning "Package list is empty."
        exit
    }
    
    Write-Host "Loaded $($TargetConfig.Count) packages from config."
    
    # 2. Analyze
    Get-SystemState
    $Plan = Analyze-Packages -ConfigList $TargetConfig
    
    # 3. Show Summary
    Write-Host "`nAnalysis Complete. Summary:" -ForegroundColor White
    $Plan | Select-Object Id, Status | Format-Table -AutoSize
    
    # 4. Execute
    Execute-Plan -Plan $Plan
    
    Write-Host "`nAll operations completed successfully." -ForegroundColor Green
}
catch {
    Write-Error "Critical Error: $_"
    exit 1
}

$ErrorActionPreference = "Stop"
# Set console encoding to UTF8 to prevent character display issues
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Script:PackageListFile = Join-Path $PSScriptRoot "packages.txt"

# --- Helper Functions ---

function Show-Banner {
    <#
    .SYNOPSIS
        Clears the host screen and displays the ASCII banner.
    #>
    Clear-Host
    $banner = @"
__        _____ _   _ ____  _____ _____ 
\ \      / /_ _| \ | / ___|| ____|_   _|
 \ \ /\ / / | ||  \| \___ \|  _|   | |  
  \ V  V /  | || |\  |___) | |___  | |  
   \_/\_/  |___|_| \_|____/|_____| |_|  
"@
    Write-Host $banner -ForegroundColor Cyan
    Write-Host "`nInitializing Winget Automation Tool...`n" -ForegroundColor Gray
}

function Get-CleanedPackageList {
    <#
    .SYNOPSIS
        Reads the package list, removing comments and empty lines.
    #>
    param ([string]$FilePath)

    if (-not (Test-Path $FilePath)) {
        throw "Package list file not found at: $FilePath"
    }

    return Get-Content $FilePath | Where-Object { 
        $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*$' 
    } | ForEach-Object { $_.Trim() }
}

function Get-ActionPlan {
    <#
    .SYNOPSIS
        Scans the package list and determines the required action (Install/Update/Skip) for each item.
        Optimizes performance by fetching the upgrade list once instead of per package.
    #>
    param ([string[]]$PackageIds)

    Write-Host "[-] Analyzing system and fetching update list (This process may take a moment)..." -ForegroundColor Yellow
    
    # Fetch list of all upgradable packages once (for performance optimization)
    # Suppress stderr (2>$null) as winget might return non-zero exit codes if no updates are found.
    $upgradableList = winget upgrade --accept-source-agreements 2>$null | Out-String

    $tasks = @()

    foreach ($id in $PackageIds) {
        $statusObj = [PSCustomObject]@{
            Id = $id
            Action = "Skip"
            Message = "Up to date / Installed"
        }

        # 1. Check: Is the package installed at all?
        $isInstalled = (winget list -e --id $id --accept-source-agreements 2>$null) -match $id

        if (-not $isInstalled) {
            $statusObj.Action = "Install"
            $statusObj.Message = "Not Installed -> To be Installed"
        }
        # 2. Check: Is it installed but listed in the upgradable list?
        elseif ($upgradableList -match $id) {
            $statusObj.Action = "Update"
            $statusObj.Message = "Outdated -> To be Updated"
        }

        $tasks += $statusObj
    }

    return $tasks
}

function Invoke-WingetAction {
    <#
    .SYNOPSIS
        Executes the determined action (Install or Upgrade).
    #>
    param (
        [string]$Id,
        [string]$Action
    )

    if ($Action -eq "Install") {
        Write-Host " [+] Installing: $Id" -ForegroundColor Cyan
        winget install -e --id $Id --silent --accept-package-agreements --accept-source-agreements
    }
    elseif ($Action -eq "Update") {
        Write-Host " [^] Updating: $Id" -ForegroundColor Magenta
        winget upgrade -e --id $Id --silent --accept-package-agreements --accept-source-agreements
    }
}

# --- Main Execution Flow ---

function Main {
    Show-Banner
    
    try {
        # 1. Retrieve package list
        $packages = Get-CleanedPackageList -FilePath $Script:PackageListFile
        
        # 2. Perform Analysis (Planning Phase)
        $actionPlan = Get-ActionPlan -PackageIds $packages
        
        # Display Analysis Report (User visibility)
        Write-Host "`n--- ANALYSIS REPORT ---" -ForegroundColor White
        $actionPlan | Format-Table @{Label="Package ID"; Expression={$_.Id}}, @{Label="Status"; Expression={$_.Message}} -AutoSize

        # Filter only items requiring action
        $todoList = $actionPlan | Where-Object { $_.Action -ne "Skip" }

        if ($todoList.Count -eq 0) {
            Write-Host "`n[OK] All packages are already installed and up to date." -ForegroundColor Green
            return
        }

        # 3. Execution Phase
        Write-Host "`n--- EXECUTION STARTED ---" -ForegroundColor White
        foreach ($item in $todoList) {
            try {
                Invoke-WingetAction -Id $item.Id -Action $item.Action
            }
            catch {
                Write-Error "ERROR [$($item.Id)]: $_"
            }
        }
        
        Write-Host "`n[DONE] All operations completed successfully." -ForegroundColor Green
    }
    catch {
        Write-Error "An unexpected error occurred: $_"
    }
}

# Run the script
Main

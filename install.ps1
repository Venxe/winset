$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Script:PackageListFile = Join-Path $PSScriptRoot "packages.txt"

# --- Helper Functions ---

function Show-Banner {
    Clear-Host
    # Minimalist, clean header
    Write-Host "`n :: WINGET AUTOMATION TOOL ::" -ForegroundColor Cyan -BackgroundColor Black
    Write-Host "    v2.1 | Optimized & Auto-Close`n" -ForegroundColor DarkGray
}

function Get-CleanedPackageList {
    param ([string]$FilePath)
    if (-not (Test-Path $FilePath)) { throw "Package list file not found at: $FilePath" }
    return Get-Content $FilePath | Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*$' } | ForEach-Object { $_.Trim() }
}

function Get-ActionPlan {
    param ([string[]]$PackageIds)

    # --- OPTIMIZATION START ---
    # Fetching heavy data ONCE instead of per-package.
    Write-Host " [-] Fetching system data..." -ForegroundColor Gray
    
    # 1. Get all installed packages in one go
    $installedRaw = winget list --accept-source-agreements 2>$null | Out-String
    
    # 2. Get all available upgrades in one go
    $upgradableRaw = winget upgrade --accept-source-agreements 2>$null | Out-String
    # --- OPTIMIZATION END ---

    $tasks = @()
    $total = $PackageIds.Count
    $current = 0

    foreach ($id in $PackageIds) {
        $current++
        # Update progress bar (Minimalist UI)
        Write-Progress -Activity "Analyzing Packages" -Status "Checking: $id" -PercentComplete (($current / $total) * 100)

        $statusObj = [PSCustomObject]@{
            Id = $id
            Action = "Skip"
        }

        # Logic: Check against the cached strings (Much faster than calling winget.exe repeatedly)
        $isInstalled = $installedRaw -match $id
        $needsUpdate = $upgradableRaw -match $id

        if (-not $isInstalled) {
            $statusObj.Action = "Install"
        }
        elseif ($needsUpdate) {
            $statusObj.Action = "Update"
        }

        $tasks += $statusObj
    }
    
    Write-Progress -Activity "Analyzing Packages" -Completed
    return $tasks
}

function Stop-TargetProcess {
    <#
    .SYNOPSIS
        Attempts to find and stop a process associated with the package ID.
        Uses a heuristic based on the last part of the ID (e.g., 'Mozilla.Firefox' -> 'Firefox').
    #>
    param ([string]$PackageId)

    $guessedProcessName = $PackageId.Split('.')[-1]
    
    # Try to get the process silently
    $process = Get-Process -Name $guessedProcessName -ErrorAction SilentlyContinue

    if ($process) {
        Write-Host "  [!] Closing running app: $guessedProcessName" -ForegroundColor Yellow
        try {
            $process | Stop-Process -Force -ErrorAction Stop
        }
        catch {
            Write-Warning "Could not force close $guessedProcessName. Update might fail if files are locked."
        }
    }
}

function Invoke-WingetAction {
    param ([string]$Id, [string]$Action)

    # Pre-flight check: Close the app if it's running
    Stop-TargetProcess -PackageId $Id

    if ($Action -eq "Install") {
        Write-Host " [+] Installing : $Id" -ForegroundColor Cyan
        winget install -e --id $Id --silent --accept-package-agreements --accept-source-agreements
    }
    elseif ($Action -eq "Update") {
        Write-Host " [^] Updating   : $Id" -ForegroundColor Magenta
        winget upgrade -e --id $Id --silent --accept-package-agreements --accept-source-agreements
    }
}

# --- Main Execution Flow ---

function Main {
    Show-Banner
    
    try {
        $packages = Get-CleanedPackageList -FilePath $Script:PackageListFile
        
        # 2. Perform Optimized Analysis
        $actionPlan = Get-ActionPlan -PackageIds $packages
        
        # 3. Minimalist Dashboard Output
        $toInstall = ($actionPlan | Where-Object { $_.Action -eq "Install" }).Count
        $toUpdate  = ($actionPlan | Where-Object { $_.Action -eq "Update" }).Count
        $upToDate  = ($actionPlan | Where-Object { $_.Action -eq "Skip" }).Count
        
        Write-Host "--- SYSTEM STATUS ---" -ForegroundColor White
        Write-Host " Total Packages : $($packages.Count)"
        Write-Host " Up to Date     : $upToDate" -ForegroundColor DarkGreen
        Write-Host " To Install     : $toInstall" -ForegroundColor Cyan
        Write-Host " To Update      : $toUpdate" -ForegroundColor Magenta
        Write-Host "---------------------`n" -ForegroundColor White

        $todoList = $actionPlan | Where-Object { $_.Action -ne "Skip" }

        if ($todoList.Count -eq 0) {
            Write-Host " [OK] System is fully up to date." -ForegroundColor Green
            return
        }

        # 4. Execution
        Write-Host "Processing Queue..." -ForegroundColor Yellow
        foreach ($item in $todoList) {
            try {
                Invoke-WingetAction -Id $item.Id -Action $item.Action
            }
            catch {
                Write-Error " ! Error processing $($item.Id): $_"
            }
        }
        
        Write-Host "`n [DONE] Operations completed." -ForegroundColor Green
    }
    catch {
        Write-Error "Critical Error: $_"
    }
}

Main

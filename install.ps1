$ErrorActionPreference = "Stop"
$Script:PackageListFile = Join-Path $PSScriptRoot "packages.txt"

# --- Helper Functions ---

function Get-CleanedPackageList {
    <#
    .SYNOPSIS
        Parses the package file, removing comments and empty lines.
    #>
    param (
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath)) {
        Write-Error "Package list file not found at: $FilePath"
    }

    # Filter out lines starting with '#' or whitespace
    return Get-Content $FilePath | Where-Object { 
        $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*$' 
    }
}

function Test-IsPackageInstalled {
    <#
    .SYNOPSIS
        Checks if a specific package ID is currently installed.
    #>
    param (
        [string]$Id
    )
    
    # 'winget list' returns exit code 0 if found, non-zero if not found (in strictly managed envs),
    # but parsing string output is more reliable for exact ID matching across versions.
    $result = winget list -e --id $Id --accept-source-agreements 2>&1
    return ($result -match $Id)
}

function Invoke-WingetInstall {
    <#
    .SYNOPSIS
        Installs a new package.
    #>
    param (
        [string]$Id
    )

    Write-Host " [+] Installing: $Id" -ForegroundColor Cyan
    winget install -e --id $Id --silent --accept-package-agreements --accept-source-agreements
}

function Invoke-WingetUpgrade {
    <#
    .SYNOPSIS
        Attempts to upgrade an existing package.
    #>
    param (
        [string]$Id
    )

    Write-Host " [^] Checking for updates: $Id" -ForegroundColor Yellow
    # Winget upgrade handles the "no update available" logic internally
    winget upgrade -e --id $Id --silent --accept-package-agreements --accept-source-agreements
}

# --- Main Execution Flow ---

function Main {
    Write-Host "Starting Package Management Process..." -ForegroundColor Green
    
    try {
        # 1. Retrieve valid package IDs
        $packages = Get-CleanedPackageList -FilePath $Script:PackageListFile
        
        foreach ($packageId in $packages) {
            $packageId = $packageId.Trim()
            
            Write-Host "Processing: $packageId" -NoNewline
            
            # 2. Determine Action (Install vs Upgrade)
            $isInstalled = Test-IsPackageInstalled -Id $packageId

            if (-not $isInstalled) {
                Write-Host " -> Not Installed." -ForegroundColor Gray
                Invoke-WingetInstall -Id $packageId
            }
            else {
                Write-Host " -> Installed." -ForegroundColor Gray
                Invoke-WingetUpgrade -Id $packageId
            }
        }
        
        Write-Host "`nAll operations completed successfully." -ForegroundColor Green
    }
    catch {
        Write-Error "An unexpected error occurred: $_"
    }
}

# Run the script
Main

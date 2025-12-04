<#
.SYNOPSIS
    Automated software installation script using Winget with TXT configuration.

.DESCRIPTION
    Reads a simple text file of package IDs.
    Checks if the package is installed:
    - If YES: Attempts to upgrade it.
    - If NO: Installs it from scratch.
    Displays a custom ASCII banner at startup.

.NOTES
    File Name      : install_apps.ps1
    Config File    : packages.txt
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Configuration path
$ConfigFileName = "packages.txt"
$ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath $ConfigFileName

<#
.FUNCTION Show-Banner
.DESCRIPTION
    Clears the terminal and displays the custom ASCII art.
#>
function Show-Banner {
    Clear-Host
    
    # Using a Here-String for the ASCII art to preserve formatting
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
    # Print in a specific color (Cyan) to make it pop
    Write-Host $Banner -ForegroundColor Cyan
}

<#
.FUNCTION Get-PackageList
.DESCRIPTION
    Reads the text file, ignoring empty lines and comments.
#>
function Get-PackageList {
    param ( [string]$Path )

    if (-not (Test-Path -Path $Path)) {
        throw "Configuration file not found at: $Path"
    }

    $Content = Get-Content -Path $Path | 
               ForEach-Object { $_.Trim() } | 
               Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith("#") }

    return $Content
}

<#
.FUNCTION Install-WingetPackage
.DESCRIPTION
    Smart wrapper: Checks existence first, then decides to Install or Upgrade.
#>
function Install-WingetPackage {
    param ( [string]$PackageId )

    Write-Host "Processing: $PackageId" -ForegroundColor Yellow

    # 1. CHECK: Is the app already installed?
    # We use --exact to avoid partial matches
    $IsInstalled = (winget list --id $PackageId --exact --source winget 2>$null)

    if ($IsInstalled) {
        # --- UPGRADE PATH ---
        Write-Host " -> App exists. Checking for updates..." -NoNewline
        
        try {
            # Capture output to detect "No upgrade found" message
            # --include-unknown: Helps with apps like Tor/Discord where versioning might be tricky
            $UpgradeOutput = winget upgrade --id $PackageId --exact --silent --accept-package-agreements --accept-source-agreements --include-unknown 2>&1 | Out-String

            if ($UpgradeOutput -match "No applicable upgrade found" -or $UpgradeOutput -match "No available upgrade found") {
                Write-Host " [Already Latest Version]" -ForegroundColor Green
            }
            else {
                # If no specific 'no upgrade' msg, assume it processed an update or checked successfully
                Write-Host " [Update Process Completed]" -ForegroundColor Green
            }
        }
        catch {
            Write-Host " [Update Error: $_]" -ForegroundColor Red
        }
    }
    else {
        # --- INSTALL PATH ---
        Write-Host " -> App not found. Installing..." -NoNewline
        
        try {
            winget install --id $PackageId -e --source winget --accept-package-agreements --accept-source-agreements --silent
            Write-Host " [Installed Successfully]" -ForegroundColor Green
        }
        catch {
            Write-Error " [Installation Failed] Detail: $_"
        }
    }
    
    Write-Host "--------------------------------------------------"
}

# --- Main Execution Block ---

try {
    # 1. Initialize UI
    Show-Banner

    Write-Host "Reading package list from $ConfigFileName..." 
    $PackageList = Get-PackageList -Path $ConfigPath

    if ($null -eq $PackageList -or $PackageList.Count -eq 0) {
        Write-Warning "No valid packages found in the text file."
        exit
    }

    Write-Host "Found $($PackageList.Count) packages to process."
    Write-Host "--------------------------------------------------"

    # 2. Check Winget Availability
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "Winget is not found. Please update App Installer via Microsoft Store."
    }

    # 3. Installation Loop
    foreach ($AppId in $PackageList) {
        Install-WingetPackage -PackageId $AppId
    }

    Write-Host "`nAll operations completed." -ForegroundColor Green
}
catch {
    Write-Error "Critical Error: $_"
    exit 1
}

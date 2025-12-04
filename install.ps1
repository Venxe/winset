<#
.SYNOPSIS
    Automated software installation script using Winget with TXT configuration.

.DESCRIPTION
    Reads a simple text file of package IDs and installs them via Winget.
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
 ___   ___   _____ __  __ ___ _   _ ___    _   _  ___ ___ 
/ __| /_\ \ / /_ _|  \/  | _ ) | | | _ \  /_\ | |/ ( ) __|
\__ \/ _ \ V / | || |\/| | _ \ |_| |   / / _ \| ' <|/\__ \
|___/_/ \_\_| |___|_|_ |_|___/\___/|_|_\/_/ \_\_|\_\ |___/
\ \    / /_ _| \| / __| __|_   _|                         
 \ \/\/ / | || .` \__ \ _|  | |                           
  \_/\_/ |___|_|\_|___/___| |_|                           

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
    Wrapper function to install a single package via Winget with error handling.
#>
function Install-WingetPackage {
    param ( [string]$PackageId )

    Write-Host "Processing: $PackageId" -ForegroundColor Yellow

    try {
        # Arguments: -e (Exact), --silent (No UI), --accept-*-agreements (Auto-license)
        winget install --id $PackageId -e --source winget --accept-package-agreements --accept-source-agreements --silent
        Write-Host " [OK] Successfully processed: $PackageId" -ForegroundColor Green
    }
    catch {
        Write-Error " [ERROR] Failed to install $PackageId. Detail: $_"
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

    Write-Host "Found $($PackageList.Count) packages to install."
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

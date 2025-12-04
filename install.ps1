<#
.SYNOPSIS
    Automated software installation script using Winget with TXT configuration.

.DESCRIPTION
    Reads a package list, checks installation status, handles timeouts, 
    and verifies exit codes for robust error reporting.

.NOTES
    File Name      : install_apps.ps1
    Config File    : packages.txt
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Configuration
$ConfigFileName = "packages.txt"
$ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath $ConfigFileName
$InstallTimeoutSeconds = 600 # 10 Minutes timeout per app

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

function Get-PackageList {
    param ( [string]$Path )
    if (-not (Test-Path -Path $Path)) { throw "Configuration file not found at: $Path" }
    return Get-Content -Path $Path | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith("#") }
}

<#
.FUNCTION Run-WingetCommand
.DESCRIPTION
    Runs winget via Start-Process to handle timeouts and exit codes properly.
#>
function Run-WingetCommand {
    param (
        [string]$Arguments,
        [string]$ActionName
    )

    $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
    $ProcessInfo.FileName = "winget"
    $ProcessInfo.Arguments = $Arguments
    $ProcessInfo.RedirectStandardOutput = $false # Keep output visible
    $ProcessInfo.RedirectStandardError = $false
    $ProcessInfo.UseShellExecute = $false
    $ProcessInfo.CreateNoWindow = $true

    $Process = New-Object System.Diagnostics.Process
    $Process.StartInfo = $ProcessInfo

    try {
        $Process.Start() | Out-Null
        
        # Wait for the process with a timeout
        if ($Process.WaitForExit($InstallTimeoutSeconds * 1000)) {
            # Process finished within timeout
            return $Process.ExitCode
        }
        else {
            # Timeout reached
            $Process.Kill()
            Write-Warning " [TIMEOUT] Operation took longer than $InstallTimeoutSeconds seconds."
            return -999 # Custom code for timeout
        }
    }
    catch {
        return -1
    }
}

function Install-WingetPackage {
    param ( [string]$PackageId )

    Write-Host "Processing: $PackageId" -ForegroundColor Yellow

    # 1. CHECK: Is the app already installed?
    $CheckArgs = "list --id $PackageId --exact --source winget"
    # We use a simple execution for list as it's fast
    $ListProcess = Start-Process winget -ArgumentList $CheckArgs -NoNewWindow -PassThru -Wait
    $IsInstalled = ($ListProcess.ExitCode -eq 0)

    if ($IsInstalled) {
        # --- UPGRADE PATH ---
        Write-Host " -> App exists. Checking for updates..." -NoNewline
        
        # Arguments: --include-unknown handles apps with versioning issues
        # --disable-interactivity prevents pop-ups that hang scripts
        $UpgradeArgs = "upgrade --id $PackageId --exact --silent --accept-package-agreements --accept-source-agreements --include-unknown --disable-interactivity --force"
        
        $ExitCode = Run-WingetCommand -Arguments $UpgradeArgs -ActionName "Upgrade"

        if ($ExitCode -eq 0) {
            Write-Host " [Success/Up-to-Date]" -ForegroundColor Green
        }
        elseif ($ExitCode -eq -999) {
            Write-Host " [Skipped due to Timeout]" -ForegroundColor Red
        }
        else {
            # Winget upgrade returns specific codes if no update found, but usually 0 or generic error
            Write-Host " [Check/Update Completed (Code: $ExitCode)]" -ForegroundColor Magenta
        }
    }
    else {
        # --- INSTALL PATH ---
        Write-Host " -> App not found. Installing..." -NoNewline
        
        $InstallArgs = "install --id $PackageId -e --source winget --accept-package-agreements --accept-source-agreements --silent --disable-interactivity --force"
        
        $ExitCode = Run-WingetCommand -Arguments $InstallArgs -ActionName "Install"

        if ($ExitCode -eq 0) {
            Write-Host " [Installed Successfully]" -ForegroundColor Green
        }
        elseif ($ExitCode -eq -999) {
            Write-Host " [FAILED - TIMEOUT]" -ForegroundColor Red
            Write-Warning "The installer for $PackageId hung. It might require manual installation."
        }
        else {
            Write-Host " [FAILED - Error Code: $ExitCode]" -ForegroundColor Red
        }
    }
    
    Write-Host "--------------------------------------------------"
}

# --- Main Execution Block ---

try {
    Show-Banner
    Write-Host "Reading package list from $ConfigFileName..." 
    $PackageList = Get-PackageList -Path $ConfigPath

    if ($null -eq $PackageList -or $PackageList.Count -eq 0) {
        Write-Warning "No valid packages found."
        exit
    }

    Write-Host "Found $($PackageList.Count) packages."
    Write-Host "Timeout set to: $InstallTimeoutSeconds seconds per app."
    Write-Host "--------------------------------------------------"

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "Winget is not found. Please update App Installer via Microsoft Store."
    }

    foreach ($AppId in $PackageList) {
        Install-WingetPackage -PackageId $AppId
    }

    Write-Host "`nAll operations completed." -ForegroundColor Green
}
catch {
    Write-Error "Critical Error: $_"
    exit 1
}

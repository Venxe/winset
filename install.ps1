<#
.SYNOPSIS
    Automated software installation script with Smart Process Management & Robust Argument Handling.

.DESCRIPTION
    1. Reads 'packages.txt'. Format: "PackageID=ProcessName|CustomArguments"
    2. Uses specific argument arrays to prevent PowerShell parsing errors with spaces/parentheses.
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

function Get-PackageConfig {
    param ( [string]$Path )
    if (-not (Test-Path -Path $Path)) { throw "Configuration file not found at: $Path" }
    
    $RawContent = Get-Content -Path $Path
    $ConfigList = @()

    foreach ($Line in $RawContent) {
        $Trimmed = $Line.Trim()
        if ([string]::IsNullOrWhiteSpace($Trimmed) -or $Trimmed.StartsWith("#")) { continue }

        $PkgId = $null
        $ProcName = $null
        $Args = $null

        if ($Trimmed -match "=") {
            $FirstSplit = $Trimmed -split "=", 2
            $PkgId = $FirstSplit[0].Trim()
            $RightSide = $FirstSplit[1].Trim()

            if ($RightSide -match "\|") {
                $SecondSplit = $RightSide -split "\|", 2
                $ProcName = $SecondSplit[0].Trim()
                $Args = $SecondSplit[1].Trim()
            }
            else {
                $ProcName = $RightSide
            }
        }
        else {
            $PkgId = $Trimmed
        }

        if ([string]::IsNullOrWhiteSpace($ProcName)) { $ProcName = $null }
        if ([string]::IsNullOrWhiteSpace($Args)) { $Args = $null }

        $ConfigList += [PSCustomObject]@{
            Id          = $PkgId
            ProcessName = $ProcName
            Arguments   = $Args
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
            catch { Write-Warning "    Could not close $ProcessName." }
        }
    }
}

<#
.FUNCTION Execute-Plan
.DESCRIPTION
    Executes winget using Argument Lists (Splats) instead of Invoke-Expression.
    This fixes bugs with spaces and parentheses in file paths.
#>
<#
.FUNCTION Execute-Plan
.DESCRIPTION
    Executes commands and capturing real output.
    Checks $LASTEXITCODE to determine if installation actually succeeded.
#>
function Execute-Plan {
    param ( $Plan )
    $ToProcess = $Plan | Where-Object { $_.Status -ne $Status.UpToDate }

    if ($ToProcess.Count -eq 0) {
        Write-Host "`nAll packages are up to date! Nothing to do." -ForegroundColor Green
        return
    }

    Write-Host "`nStarting Execution Phase ($($ToProcess.Count) tasks)..." -ForegroundColor Yellow
    Write-Host "--------------------------------------------------"

    foreach ($Item in $ToProcess) {
        $Pkg = $Item.Id
        Write-Host "Processing: $Pkg" -NoNewline
        
        Stop-ConflictingProcess -ProcessName $Item.ProcessName

        # --- Base Arguments ---
        $BaseArgs = @("--id", $Pkg, "-e", "--accept-package-agreements", "--accept-source-agreements")
        
        # --- Handle Overrides vs Silent ---
        $FinalArgs = @()
        
        if (-not [string]::IsNullOrWhiteSpace($Item.Arguments)) {
            # Override parametresi ekleniyor.
            # DİKKAT: Override kullanınca varsayılan silent parametreleri silinir.
            # Yükleyicinin sessiz çalışması için gerekli komutları da arguments içine yazmalısınız.
            $FinalArgs += "--override"
            $FinalArgs += $Item.Arguments
            Write-Host " [Custom Args Applied]" -ForegroundColor DarkGray -NoNewline
        }
        else {
            # Standart sessiz kurulum
            $FinalArgs += "--silent"
        }

        # Komut Hazırlığı
        $CommandArgs = @()
        if ($Item.Status -eq $Status.Missing) {
            Write-Host " [Installing]" -ForegroundColor Cyan
            $CommandArgs = @("install") + $BaseArgs + @("--source", "winget") + $FinalArgs
        }
        elseif ($Item.Status -eq $Status.Outdated) {
            Write-Host " [Upgrading]" -ForegroundColor Magenta
            $CommandArgs = @("upgrade") + $BaseArgs + @("--include-unknown", "--force") + $FinalArgs
        }

        # --- KOMUTU ÇALIŞTIR VE ÇIKTIYI YAKALA ---
        try {
            # 2>&1 ile hem standart çıktıyı hem hataları yakalıyoruz
            $ProcessOutput = & winget $CommandArgs 2>&1 | Out-String
            
            # Winget çıkış kodunu kontrol et (0 = Başarılı)
            if ($LASTEXITCODE -eq 0) {
                Write-Host " -> Success." -ForegroundColor Green
            }
            else {
                # HATA VARSA DETAYI GÖSTER
                Write-Host "`n [!] OPERATION FAILED (Exit Code: $LASTEXITCODE)" -ForegroundColor Red
                Write-Host " Winget Output Detail:" -ForegroundColor Gray
                Write-Host $ProcessOutput -ForegroundColor DarkGray
                Write-Host "--------------------------------------------------"
            }
        }
        catch {
            Write-Error "`nCritical Script Error processing $Pkg. Detail: $_"
        }
    }
}

# --- Main Execution Block ---

try {
    Show-Banner
    $TargetConfig = Get-PackageConfig -Path $ConfigPath
    
    if ($TargetConfig.Count -eq 0) { Write-Warning "Package list is empty."; exit }
    
    Write-Host "Loaded $($TargetConfig.Count) packages from config."
    Get-SystemState
    $Plan = Analyze-Packages -ConfigList $TargetConfig
    
    Write-Host "`nAnalysis Complete. Summary:" -ForegroundColor White
    $Plan | Select-Object Id, Status | Format-Table -AutoSize
    
    Execute-Plan -Plan $Plan
    Write-Host "`nAll operations completed successfully." -ForegroundColor Green
}
catch {
    Write-Error "Critical Error: $_"
    exit 1
}

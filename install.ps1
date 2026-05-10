#Requires -Version 5.1
<#
  Yoru Terminal — installer (always downloads configs from GitHub raw).
  irm https://raw.githubusercontent.com/tprojectzdev-sys/yoru-terminal/main/install.ps1 | iex
#>

$ErrorActionPreference = 'Stop'

$script:GitHubOwner = 'tprojectzdev-sys'
$script:GitHubRepo = 'yoru-terminal'
$script:GitHubBranch = 'main'
$script:RawBase = "https://raw.githubusercontent.com/$GitHubOwner/$GitHubRepo/$GitHubBranch"

function Get-IsAdmin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-AdminHint {
    if (-not (Get-IsAdmin)) {
        Write-Host '  Re-run as Administrator if this was a permission error.' -ForegroundColor Yellow
    }
}

function Invoke-YoruDownload {
    param(
        [Parameter(Mandatory)][string]$RepoRelativePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )
    $uri = "$RawBase/$($RepoRelativePath -replace '\\', '/')"
    try {
        $dir = Split-Path -Parent $DestinationPath
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
        }
        Invoke-WebRequest -Uri $uri -OutFile $DestinationPath -UseBasicParsing -ErrorAction Stop
    } catch {
        throw "Download or write failed for '$RepoRelativePath' -> '$DestinationPath' ($uri): $($_.Exception.Message)"
    }
}

function Invoke-YoruDownloadText {
    param([Parameter(Mandatory)][string]$RepoRelativePath)
    $uri = "$RawBase/$($RepoRelativePath -replace '\\', '/')"
    try {
        $r = Invoke-WebRequest -Uri $uri -UseBasicParsing -ErrorAction Stop
        return $r.Content
    } catch {
        throw "Download failed for '$RepoRelativePath' ($uri): $($_.Exception.Message)"
    }
}

function Test-WingetAvailable {
    return [bool](Get-Command winget -CommandType Application -ErrorAction SilentlyContinue)
}

function Test-WingetPackageInstalled {
    param([Parameter(Mandatory)][string]$PackageId)
    $null = & winget list --id $PackageId -e --accept-source-agreements 2>&1
    return ($LASTEXITCODE -eq 0)
}

function Install-WingetPackageSilently {
    param([Parameter(Mandatory)][string]$PackageId)
    $out = & winget install --id $PackageId -e --silent --accept-package-agreements --accept-source-agreements 2>&1 |
        Out-String
    if ($LASTEXITCODE -eq 0) { return }
    if ($out -match '(?i)already installed|found an existing package') { return }
    throw "winget install failed for $PackageId (exit $LASTEXITCODE): $out"
}

function Install-WingetToolIfMissing {
    param(
        [Parameter(Mandatory)][string]$PackageId,
        [Parameter(Mandatory)][string]$DisplayName
    )
    if (Test-WingetPackageInstalled -PackageId $PackageId) {
        Write-Host "  [ok] $DisplayName"
        return
    }
    Write-Host "  [+] installing $DisplayName..."
    Install-WingetPackageSilently -PackageId $PackageId
    Write-Host "  [ok] $DisplayName"
}

function Test-0xProtoFontHKLM {
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    if (-not (Test-Path -LiteralPath $key)) { return $false }
    try {
        $p = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
        foreach ($prop in $p.PSObject.Properties) {
            if ($prop.Name -match '^PS') { continue }
            if ($prop.Name -like '*0xProto*') { return $true }
        }
    } catch {
        Write-Host "  [!] Could not read HKLM Fonts (font check skipped): $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
    return $false
}

try {
    Write-Host ''
    Write-Host '夜 Yoru Terminal — Installer' -ForegroundColor Red
    Write-Host '────────────────────────────' -ForegroundColor DarkRed
    Write-Host ''

    if (-not (Test-WingetAvailable)) {
        Write-Host '[!] winget not found. Install App Installer from the Microsoft Store, then re-run.' -ForegroundColor Red
        exit 1
    }

    $pwshInstalledNow = $false
    try {
        Install-WingetToolIfMissing -PackageId 'Fastfetch-cli.Fastfetch' -DisplayName 'fastfetch'
    } catch {
        Write-Host "[!] fastfetch step failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-AdminHint
        exit 1
    }

    try {
        Install-WingetToolIfMissing -PackageId 'Starship.Starship' -DisplayName 'starship'
    } catch {
        Write-Host "[!] starship step failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-AdminHint
        exit 1
    }

    try {
        if (Test-WingetPackageInstalled -PackageId 'Microsoft.PowerShell') {
            Write-Host '  [ok] PowerShell 7'
        } else {
            Write-Host '  [+] installing PowerShell 7...'
            Install-WingetPackageSilently -PackageId 'Microsoft.PowerShell'
            Write-Host '  [ok] PowerShell 7'
            $pwshInstalledNow = $true
        }
    } catch {
        Write-Host "[!] PowerShell 7 step failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-AdminHint
        exit 1
    }

    if ($pwshInstalledNow) {
        Write-Host ''
        Write-Host '  [!] PowerShell 7 was just installed. Close all terminals, reopen Windows Terminal,' -ForegroundColor Yellow
        Write-Host '      set PowerShell 7 as the default profile, then run this installer again if needed.' -ForegroundColor Yellow
        Write-Host ''
    }

    $fastfetchDir = Join-Path $HOME '.config\fastfetch'
    $starshipDir = Join-Path $HOME '.config\starship'
    try {
        New-Item -Force -ItemType Directory -Path $fastfetchDir -ErrorAction Stop | Out-Null
        New-Item -Force -ItemType Directory -Path $starshipDir -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "[!] Could not create config directories: $($_.Exception.Message)" -ForegroundColor Red
        Write-AdminHint
        exit 1
    }

    try {
        Invoke-YoruDownload -RepoRelativePath 'fastfetch/dragon.txt' -DestinationPath (Join-Path $fastfetchDir 'dragon.txt')
        Write-Host '  [ok] dragon.txt'
    } catch {
        Write-Host "[!] $($_.Exception.Message)" -ForegroundColor Red
        Write-AdminHint
        exit 1
    }

    try {
        Invoke-YoruDownload -RepoRelativePath 'fastfetch/config.jsonc' -DestinationPath (Join-Path $fastfetchDir 'config.jsonc')
        Write-Host '  [ok] config.jsonc'
    } catch {
        Write-Host "[!] $($_.Exception.Message)" -ForegroundColor Red
        Write-AdminHint
        exit 1
    }

    try {
        Invoke-YoruDownload -RepoRelativePath 'starship/starship.toml' -DestinationPath (Join-Path $starshipDir 'starship.toml')
        Write-Host '  [ok] starship.toml'
    } catch {
        Write-Host "[!] $($_.Exception.Message)" -ForegroundColor Red
        Write-AdminHint
        exit 1
    }

    $wtSettings = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    try {
        $wtDir = Split-Path -Parent $wtSettings
        if (-not (Test-Path -LiteralPath $wtDir)) {
            throw "Windows Terminal LocalState not found at $wtDir. Install Windows Terminal from the Store first."
        }
        if (Test-Path -LiteralPath $wtSettings) {
            Copy-Item -LiteralPath $wtSettings -Destination "$wtSettings.bak" -Force -ErrorAction Stop
            Write-Host '  [ok] settings.json.bak'
        }
        Invoke-YoruDownload -RepoRelativePath 'terminal/settings.json' -DestinationPath $wtSettings
        Write-Host '  [ok] terminal/settings.json'
        Write-Host '  [!] Replace placeholder GUIDs in settings.json with your real PowerShell 7 profile GUID.' -ForegroundColor Yellow
    } catch {
        Write-Host "[!] Windows Terminal settings step failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-AdminHint
        exit 1
    }

    $prof = $PROFILE
    if (-not $prof) {
        Write-Host '[!] $PROFILE is empty; cannot append Yoru profile.' -ForegroundColor Red
        exit 1
    }
    $profDir = Split-Path -Parent $prof
    try {
        if (-not (Test-Path -LiteralPath $profDir)) {
            New-Item -ItemType Directory -Path $profDir -Force -ErrorAction Stop | Out-Null
        }
        if (Test-Path -LiteralPath $prof) {
            $profBak = Join-Path $profDir 'profile.ps1.bak'
            Copy-Item -LiteralPath $prof -Destination $profBak -Force -ErrorAction Stop
            Write-Host '  [ok] profile.ps1.bak'
        }
        $yoruBlockMarker = '# YORU_TERMINAL_PROFILE_BLOCK'
        $yoruText = Invoke-YoruDownloadText -RepoRelativePath 'powershell/profile.ps1'
        if (Test-Path -LiteralPath $prof) {
            $existing = Get-Content -LiteralPath $prof -Raw -ErrorAction Stop
            if ($existing -and $existing.Contains($yoruBlockMarker)) {
                Write-Host '  [ok] Yoru profile block already present; skipped append.' -ForegroundColor DarkGray
            } else {
                Add-Content -LiteralPath $prof -Value "`n$yoruBlockMarker`n" -Encoding utf8 -ErrorAction Stop
                Add-Content -LiteralPath $prof -Value $yoruText -Encoding utf8 -ErrorAction Stop
                Write-Host '  [ok] Appended Yoru profile.ps1 to $PROFILE'
            }
        } else {
            Add-Content -LiteralPath $prof -Value "$yoruBlockMarker`n" -Encoding utf8 -ErrorAction Stop
            Add-Content -LiteralPath $prof -Value $yoruText -Encoding utf8 -ErrorAction Stop
            Write-Host '  [ok] Created $PROFILE with Yoru profile.ps1'
        }
    } catch {
        Write-Host "[!] PowerShell profile step failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-AdminHint
        exit 1
    }

    if (-not (Test-0xProtoFontHKLM)) {
        Write-Host ''
        Write-Host '[!] Font not installed: 0xProto Nerd Font Mono' -ForegroundColor Yellow
        Write-Host '    Download from: https://github.com/ryanoasis/nerd-fonts/releases' -ForegroundColor Yellow
        Write-Host '    Install manually then restart Windows Terminal' -ForegroundColor Yellow
        Write-Host ''
    }

    Write-Host '────────────────────────────' -ForegroundColor DarkRed
    Write-Host '[done] Restart Windows Terminal to apply changes.' -ForegroundColor Red
    Write-Host '       If dragon shows token text like ${1}, set type to ''file'' in config.jsonc' -ForegroundColor DarkGray
    Write-Host '       Replace placeholder GUIDs in settings.json with your actual PowerShell 7 GUID' -ForegroundColor DarkGray
    Write-Host ''
} catch {
    Write-Host "[!] Unexpected failure: $($_.Exception.Message)" -ForegroundColor Red
    Write-AdminHint
    exit 1
}

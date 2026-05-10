#Requires -Version 5.1
<#
  Yoru Terminal — one-command installer.
  Local:  .\install.ps1
  Remote: irm https://raw.githubusercontent.com/OWNER/yoru-terminal/main/install.ps1 | iex
#>

$ErrorActionPreference = 'Continue'

$RepoRawBase = 'https://raw.githubusercontent.com/OWNER/yoru-terminal/main'
if ($PSScriptRoot) {
    $ContentRoot = $PSScriptRoot
} else {
    $ContentRoot = $null
}

function Get-YoruFile {
    param(
        [Parameter(Mandatory)][string]$RelativePath
    )
    $rel = $RelativePath -replace '/', '\'
    if ($ContentRoot) {
        $local = Join-Path $ContentRoot $rel
        if (-not (Test-Path -LiteralPath $local)) {
            throw "Missing repo file: $local (run from repo root or use irm|iex from GitHub)"
        }
        return $local
    }
    $url = "$RepoRawBase/$($RelativePath -replace '\\', '/')"
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
        return $tmp
    } catch {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        throw "Download failed ($url): $($_.Exception.Message)"
    }
}

function Copy-YoruFile {
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$Destination
    )
    $src = Get-YoruFile -RelativePath $RelativePath
    try {
        $destDir = Split-Path -Parent $Destination
        if (-not (Test-Path -LiteralPath $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force -ErrorAction Stop | Out-Null
        }
        Copy-Item -LiteralPath $src -Destination $Destination -Force -ErrorAction Stop
    } finally {
        if (-not $ContentRoot) {
            Remove-Item -LiteralPath $src -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-Winget {
    return [bool](Get-Command winget -CommandType Application -ErrorAction SilentlyContinue)
}

function Test-WingetPackageInstalled {
    param([Parameter(Mandatory)][string]$Id)
    winget list -e --id $Id --accept-source-agreements 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Install-WingetPackage {
    param([Parameter(Mandatory)][string]$Id)
    Write-Host "  [+] installing $Id..."
    $out = & winget install -e --id $Id --accept-source-agreements --accept-package-agreements --silent 2>&1 |
        Out-String
    if ($LASTEXITCODE -eq 0) { return }
    if ($out -match '(?i)already installed|found an existing package') {
        return
    }
    throw "winget install failed for $Id (exit $LASTEXITCODE): $out"
}

function Test-WingetUpgradeAvailable {
    param([Parameter(Mandatory)][string]$Id)
    if (-not (Test-WingetPackageInstalled -Id $Id)) { return $false }
    $out = winget upgrade -e --id $Id --include-unknown --accept-source-agreements 2>&1 | Out-String
    if ($out -match '(?i)No available upgrade|No applicable upgrade|No upgrades available') {
        return $false
    }
    if ($out -match [regex]::Escape($Id)) { return $true }
    return $false
}

function Invoke-WingetUpgradePrompt {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Label
    )
    if (-not (Test-WingetUpgradeAvailable -Id $Id)) { return }
    $ans = Read-Host "  A newer $Label is available via winget. Update now? (Y/n)"
    if ($ans -eq '' -or $ans -match '^[Yy]') {
        Write-Host "  [+] upgrading $Label..."
        $upOut = & winget upgrade -e --id $Id --accept-source-agreements --accept-package-agreements --silent 2>&1 |
            Out-String
        if ($LASTEXITCODE -ne 0) {
            $snippet = if ($upOut.Length -gt 400) { $upOut.Substring(0, 400) + '…' } else { $upOut }
            Write-Host "  [!] winget upgrade exited with $LASTEXITCODE for $Id. Output: $snippet"
        }
    }
}

function Ensure-Dependency {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Label,
        [Parameter()][string]$CommandName = $null
    )
    $hasCmd = $false
    if ($CommandName) {
        $hasCmd = [bool](Get-Command $CommandName -CommandType Application -ErrorAction SilentlyContinue)
    }
    $hasPkg = Test-WingetPackageInstalled -Id $Id
    if ($hasCmd -or $hasPkg) {
        Write-Host "  [ok] $Label"
        if (Test-WingetPackageInstalled -Id $Id) {
            Invoke-WingetUpgradePrompt -Id $Id -Label $Label
        }
        return
    }
    try {
        Install-WingetPackage -Id $Id
        Write-Host "  [ok] $Label"
    } catch {
        Write-Host "  [!] $Label install failed: $($_.Exception.Message)"
        if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Host "  Try re-running this installer from an elevated PowerShell (Run as administrator)."
        }
        throw
    }
}

function Test-0xProtoNerdFont {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
        'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    )
    foreach ($key in $keys) {
        if (-not (Test-Path -LiteralPath $key)) { continue }
        $p = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        if (-not $p) { continue }
        foreach ($prop in $p.PSObject.Properties) {
            if ($prop.Name -match '^PS') { continue }
            if ($prop.Name -match '0xProto.*Nerd Font Mono') {
                return $true
            }
        }
    }
    return $false
}

# --- header ---
Write-Host ''
Write-Host '夜 Yoru Terminal — Installer'
Write-Host '────────────────────────────'
Write-Host ''

if (-not (Test-Winget)) {
    Write-Host '[!] winget not found. Install App Installer from the Microsoft Store, then re-run.'
    exit 1
}

try {
    Ensure-Dependency -Id 'Fastfetch-cli.Fastfetch' -Label 'fastfetch' -CommandName 'fastfetch'
    Ensure-Dependency -Id 'Starship.Starship' -Label 'starship' -CommandName 'starship'
    Ensure-Dependency -Id 'Microsoft.WindowsTerminal' -Label 'Windows Terminal' -CommandName 'wt'
} catch {
    Write-Host ''
    Write-Host "[!] Dependency step failed: $($_.Exception.Message)"
    exit 1
}

Write-Host ''

# --- config copy ---
$fastfetchDir = Join-Path $HOME '.config\fastfetch'
$starshipDir = Join-Path $HOME '.config\starship'

foreach ($d in @($fastfetchDir, $starshipDir)) {
    try {
        if (-not (Test-Path -LiteralPath $d)) {
            New-Item -ItemType Directory -Path $d -Force -ErrorAction Stop | Out-Null
        }
    } catch {
        Write-Host "  [!] Could not create directory ${d}: $($_.Exception.Message)"
        if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Host '  If this was a permission error, re-run as administrator.'
        }
        exit 1
    }
}

foreach ($copy in @(
        @{ Rel = 'fastfetch\dragon.txt'; Dest = (Join-Path $fastfetchDir 'dragon.txt'); Label = 'fastfetch/dragon.txt' }
        @{ Rel = 'fastfetch\config.jsonc'; Dest = (Join-Path $fastfetchDir 'config.jsonc'); Label = 'fastfetch/config.jsonc' }
        @{ Rel = 'starship\starship.toml'; Dest = (Join-Path $starshipDir 'starship.toml'); Label = 'starship/starship.toml' }
    )) {
    try {
        Copy-YoruFile -RelativePath $copy.Rel -Destination $copy.Dest
        Write-Host "  [ok] $($copy.Label)"
    } catch {
        Write-Host "  [!] Failed $($copy.Label): $($_.Exception.Message)"
        if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Host '  If this was a permission error, re-run as administrator.'
        }
        exit 1
    }
}

$wtLocalState = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
if (-not (Test-Path -LiteralPath $wtLocalState)) {
    $pkgStable = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'Microsoft.WindowsTerminal_*' -and $_.Name -notlike '*TerminalPreview*' } |
        Select-Object -First 1
    if ($pkgStable) {
        $wtLocalState = Join-Path $pkgStable.FullName 'LocalState'
    } else {
        $pkgAny = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -Filter 'Microsoft.WindowsTerminal*' -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($pkgAny) {
            $wtLocalState = Join-Path $pkgAny.FullName 'LocalState'
        }
    }
}
$wtSettings = Join-Path $wtLocalState 'settings.json'

try {
    if (-not (Test-Path -LiteralPath $wtLocalState)) {
        throw "Windows Terminal LocalState folder not found. Install Windows Terminal from the Store, then re-run."
    }
    if (Test-Path -LiteralPath $wtSettings) {
        Copy-Item -LiteralPath $wtSettings -Destination "$wtSettings.bak" -Force -ErrorAction Stop
        Write-Host '  [ok] Windows Terminal settings.json.bak'
    }
    Copy-YoruFile -RelativePath 'terminal\settings.json' -Destination $wtSettings
    Write-Host '  [ok] terminal/settings.json'
} catch {
    Write-Host "  [!] Windows Terminal settings copy failed: $($_.Exception.Message)"
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host '  If this was a permission error, re-run as administrator.'
    }
    exit 1
}

try {
    $prof = $PROFILE
    if (-not $prof) {
        throw 'PowerShell $PROFILE path is empty.'
    }
    $profDir = Split-Path -Parent $prof
    if (-not (Test-Path -LiteralPath $profDir)) {
        New-Item -ItemType Directory -Path $profDir -Force -ErrorAction Stop | Out-Null
    }
    if (Test-Path -LiteralPath $prof) {
        Copy-Item -LiteralPath $prof -Destination "$prof.bak" -Force -ErrorAction Stop
        Write-Host '  [ok] PowerShell profile.bak'
    }
    Copy-YoruFile -RelativePath 'powershell\profile.ps1' -Destination $prof
    Write-Host '  [ok] powershell/profile.ps1 → $PROFILE'
} catch {
    Write-Host "  [!] PowerShell profile copy failed: $($_.Exception.Message)"
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host '  If this was a permission error, re-run as administrator.'
    }
    exit 1
}

Write-Host ''
if (-not (Test-0xProtoNerdFont)) {
    Write-Host '  Font "0xProto Nerd Font Mono" not detected.'
    Write-Host '  Install manually from: https://github.com/ryanoasis/nerd-fonts/releases'
    Write-Host ''
}

Write-Host '────────────────────────────'
Write-Host '[done] Yoru Terminal is ready.'
Write-Host 'Restart Windows Terminal to apply all changes.'
Write-Host ''

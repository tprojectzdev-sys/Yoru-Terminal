#Requires -Version 5.1
<#
  Yoru Terminal — Sumi-e Crimson deployment (raw GitHub only).
  irm https://raw.githubusercontent.com/tprojectzdev-sys/yoru-terminal/main/install.ps1 | iex
#>

$ErrorActionPreference = 'Stop'

$script:GitHubOwner = 'tprojectzdev-sys'
$script:GitHubRepo = 'yoru-terminal'
$script:GitHubBranch = 'main'
$script:RawBase = "https://raw.githubusercontent.com/$GitHubOwner/$GitHubRepo/$GitHubBranch"
$script:WinPowerShellWtGuid = '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}'
$script:Summary = [ordered]@{
    Theme              = 'Sumi-e Crimson'
    TerminalSettings   = $false
    Fastfetch          = $false
    Starship           = $false
    PowerShellProfile  = 'unchanged'
    Font               = 'unknown'
    GuidSource         = ''
}

# --- theme output helpers ---
function Get-IsAdmin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-AdminHint {
    if (-not (Get-IsAdmin)) {
        Write-Host '  Re-run as Administrator if this was a permission error.' -ForegroundColor Yellow
    }
}

function Write-YoruSection {
    param([Parameter(Mandatory)][string]$Title)
    Write-Host ''
    Write-Host "  $Title" -ForegroundColor Red
    Write-Host '  ───────────────────────────' -ForegroundColor DarkRed
}

function Write-YoruOk {
    param([string]$Message)
    Write-Host "  [ok] $Message" -ForegroundColor Green
}

function Write-YoruNote {
    param([string]$Message)
    Write-Host "      $Message" -ForegroundColor DarkGray
}

function New-YoruTimestampedBackup {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$Label
    )
    if (-not (Test-Path -LiteralPath $SourcePath)) {
        return $null
    }
    $dir = Split-Path -Parent $SourcePath
    $name = [System.IO.Path]::GetFileName($SourcePath)
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dest = Join-Path $dir "${name}.yoru-backup-${ts}.bak"
    Copy-Item -LiteralPath $SourcePath -Destination $dest -Force -ErrorAction Stop
    Write-YoruOk "$Label backup saved"
    Write-YoruNote $dest
    return $dest
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
        Write-YoruOk $DisplayName
        return
    }
    Write-Host "  [+] installing $DisplayName..." -ForegroundColor Yellow
    Install-WingetPackageSilently -PackageId $PackageId
    Write-YoruOk $DisplayName
}

function ConvertFrom-JsoncLoose {
    param([Parameter(Mandatory)][string]$Text)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^\s*//') { continue }
        [void]$sb.AppendLine($line)
    }
    return ($sb.ToString() | ConvertFrom-Json)
}

function Get-WtPreferredPowerShellGuid {
    param([string]$ExistingSettingsPath)
    if (-not $ExistingSettingsPath -or -not (Test-Path -LiteralPath $ExistingSettingsPath)) {
        return @{
            Guid   = $script:WinPowerShellWtGuid
            Source = 'default (Windows PowerShell — no existing settings.json)'
        }
    }
    try {
        $raw = Get-Content -LiteralPath $ExistingSettingsPath -Raw -ErrorAction Stop
        $j = ConvertFrom-JsoncLoose -Text $raw
        if (-not $j.profiles -or -not $j.profiles.list) {
            return @{
                Guid   = $script:WinPowerShellWtGuid
                Source = 'default (no profiles.list in existing file)'
            }
        }
        foreach ($p in $j.profiles.list) {
            $cmd = [string]$p.commandline
            $nm = [string]$p.name
            if ($cmd -match '(?i)[\\/]pwsh(\.exe)?(\s|$)' -or $nm -match '(?i)PowerShell\s*7') {
                return @{
                    Guid   = [string]$p.guid
                    Source = 'existing profile: PowerShell 7 / pwsh'
                }
            }
        }
        foreach ($p in $j.profiles.list) {
            if ([string]$p.source -match '(?i)PowershellCore') {
                return @{
                    Guid   = [string]$p.guid
                    Source = 'existing profile: Windows.Terminal.PowershellCore'
                }
            }
        }
        return @{
            Guid   = $script:WinPowerShellWtGuid
            Source = 'fallback (use classic Windows PowerShell GUID)'
        }
    } catch {
        return @{
            Guid   = $script:WinPowerShellWtGuid
            Source = "fallback (parse error: $($_.Exception.Message))"
        }
    }
}

function Apply-YoruTerminalSettingsText {
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$PsGuid,
        [Parameter(Mandatory)][bool]$UseWindowsPowerShellFallback
    )
    $c = $Content -replace '\{powershell-guid\}', $PsGuid
    if ($UseWindowsPowerShellFallback) {
        $c = $c -replace '(?m)"commandline"\s*:\s*"pwsh\.exe -NoLogo"', '"commandline": "%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"'
        $c = $c -replace '(?m)"name"\s*:\s*"PowerShell 7"', '"name": "Windows PowerShell"'
    }
    return $c
}

function Test-Yoru0xProtoFont {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
        'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    )
    foreach ($key in $keys) {
        if (-not (Test-Path -LiteralPath $key)) { continue }
        try {
            $p = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            foreach ($prop in $p.PSObject.Properties) {
                if ($prop.Name -match '^PS') { continue }
                if ($prop.Name -like '*0xProto*') { return $true }
            }
        } catch {
            Write-Host "  [!] Font registry read skipped ($key): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    return $false
}

function Install-YoruFontFromNerdFonts {
    <#
      Reserved for a future safe font install path (e.g. user-approved download + admin font copy).
      Intentionally empty — avoids silent system changes.
    #>
    param()
    return $false
}

try {
    Write-Host ''
    Write-Host '  夜 Yoru Terminal — Installer' -ForegroundColor Red
    Write-Host '  Sumi-e Crimson deployment' -ForegroundColor DarkRed
    Write-Host '  ───────────────────────────' -ForegroundColor DarkRed
    Write-Host ''

    if (-not (Test-WingetAvailable)) {
        Write-Host '  [!] winget not found. Install App Installer from the Microsoft Store, then re-run.' -ForegroundColor Red
        exit 1
    }

    # --- Core ---
    Write-YoruSection 'Core'
    $pwshInstalledNow = $false
    try {
        Install-WingetToolIfMissing -PackageId 'Fastfetch-cli.Fastfetch' -DisplayName 'fastfetch'
    } catch {
        Write-Host "  [!] fastfetch: $($_.Exception.Message)" -ForegroundColor Red
        Write-AdminHint
        exit 1
    }

    try {
        Install-WingetToolIfMissing -PackageId 'Starship.Starship' -DisplayName 'starship'
    } catch {
        Write-Host "  [!] starship: $($_.Exception.Message)" -ForegroundColor Red
        Write-AdminHint
        exit 1
    }

    try {
        if (Test-WingetPackageInstalled -PackageId 'Microsoft.PowerShell') {
            Write-YoruOk 'PowerShell 7'
        } else {
            Write-Host '  [+] installing PowerShell 7...' -ForegroundColor Yellow
            Install-WingetPackageSilently -PackageId 'Microsoft.PowerShell'
            Write-YoruOk 'PowerShell 7'
            $pwshInstalledNow = $true
        }
    } catch {
        Write-Host "  [!] PowerShell 7: $($_.Exception.Message)" -ForegroundColor Red
        Write-AdminHint
        exit 1
    }

    if ($pwshInstalledNow) {
        Write-Host ''
        Write-Host '  [!] PowerShell 7 was just installed. Close every terminal, reopen Windows Terminal,' -ForegroundColor Yellow
        Write-Host '      add or select a PowerShell 7 tab once, then run this installer again so we can match its profile GUID.' -ForegroundColor Yellow
        Write-Host ''
    }

    # --- Assets ---
    Write-YoruSection 'Assets'
    $fastfetchDir = Join-Path $HOME '.config\fastfetch'
    $starshipDir = Join-Path $HOME '.config\starship'
    try {
        New-Item -Force -ItemType Directory -Path $fastfetchDir -ErrorAction Stop | Out-Null
        New-Item -Force -ItemType Directory -Path $starshipDir -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "  [!] Config folders: $($_.Exception.Message)" -ForegroundColor Red
        Write-AdminHint
        exit 1
    }

    try {
        Invoke-YoruDownload -RepoRelativePath 'fastfetch/dragon.txt' -DestinationPath (Join-Path $fastfetchDir 'dragon.txt')
        Write-YoruOk 'fastfetch/dragon.txt'
        $script:Summary.Fastfetch = $true
    } catch {
        Write-Host "  [!] $($_.Exception.Message)" -ForegroundColor Red
        Write-AdminHint
        exit 1
    }

    try {
        Invoke-YoruDownload -RepoRelativePath 'fastfetch/config.jsonc' -DestinationPath (Join-Path $fastfetchDir 'config.jsonc')
        Write-YoruOk 'fastfetch/config.jsonc'
    } catch {
        Write-Host "  [!] $($_.Exception.Message)" -ForegroundColor Red
        Write-AdminHint
        exit 1
    }

    try {
        Invoke-YoruDownload -RepoRelativePath 'starship/starship.toml' -DestinationPath (Join-Path $starshipDir 'starship.toml')
        Write-YoruOk 'starship/starship.toml'
        $script:Summary.Starship = $true
    } catch {
        Write-Host "  [!] $($_.Exception.Message)" -ForegroundColor Red
        Write-AdminHint
        exit 1
    }

    # --- Terminal ---
    Write-YoruSection 'Terminal'
    $wtSettings = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    if (-not (Test-Path -LiteralPath (Split-Path -Parent $wtSettings))) {
        $pkg = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'Microsoft.WindowsTerminal_*' -and $_.Name -notlike '*TerminalPreview*' } |
            Select-Object -First 1
        if (-not $pkg) {
            $pkg = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -Filter 'Microsoft.WindowsTerminal*' -ErrorAction SilentlyContinue |
                Select-Object -First 1
        }
        if ($pkg) {
            $wtSettings = Join-Path $pkg.FullName 'LocalState\settings.json'
        }
    }

    try {
        $wtDir = Split-Path -Parent $wtSettings
        if (-not (Test-Path -LiteralPath $wtDir)) {
            throw "Windows Terminal LocalState not found. Install Windows Terminal from the Microsoft Store, then re-run."
        }

        $guidInfo = Get-WtPreferredPowerShellGuid -ExistingSettingsPath $wtSettings
        $script:Summary.GuidSource = $guidInfo.Source
        $useWinPs = ($guidInfo.Guid -eq $script:WinPowerShellWtGuid)

        if (Test-Path -LiteralPath $wtSettings) {
            $null = New-YoruTimestampedBackup -SourcePath $wtSettings -Label 'Windows Terminal settings.json'
        } else {
            Write-YoruNote 'No existing settings.json (first run).'
        }

        $settingsRaw = Invoke-YoruDownloadText -RepoRelativePath 'terminal/settings.json'
        $settingsOut = Apply-YoruTerminalSettingsText -Content $settingsRaw -PsGuid $guidInfo.Guid -UseWindowsPowerShellFallback $useWinPs
        Set-Content -LiteralPath $wtSettings -Value $settingsOut -Encoding utf8 -ErrorAction Stop
        Write-YoruOk 'terminal/settings.json deployed'
        $script:Summary.TerminalSettings = $true

        Write-YoruNote "defaultProfile GUID: $($guidInfo.Guid)"
        Write-YoruNote "detection: $($guidInfo.Source)"
        if ($guidInfo.Guid -notmatch '^\{[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}$') {
            Write-Host '  [!] GUID format unexpected — confirm defaultProfile in Windows Terminal → Settings → JSON.' -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [!] Windows Terminal: $($_.Exception.Message)" -ForegroundColor Red
        Write-AdminHint
        exit 1
    }

    # --- PowerShell ---
    Write-YoruSection 'PowerShell'
    $prof = $PROFILE
    if (-not $prof) {
        Write-Host '  [!] `$PROFILE is empty; cannot append Yoru profile.' -ForegroundColor Red
        exit 1
    }
    $profDir = Split-Path -Parent $prof
    try {
        if (-not (Test-Path -LiteralPath $profDir)) {
            New-Item -ItemType Directory -Path $profDir -Force -ErrorAction Stop | Out-Null
        }
        if (Test-Path -LiteralPath $prof) {
            $null = New-YoruTimestampedBackup -SourcePath $prof -Label 'PowerShell profile'
        }

        $yoruBlockMarker = '# YORU_TERMINAL_PROFILE_BLOCK'
        $yoruText = Invoke-YoruDownloadText -RepoRelativePath 'powershell/profile.ps1'
        if (Test-Path -LiteralPath $prof) {
            $existing = Get-Content -LiteralPath $prof -Raw -ErrorAction Stop
            if ($existing -and $existing.Contains($yoruBlockMarker)) {
                Write-YoruOk 'Yoru profile block already present (skipped append)'
                $script:Summary.PowerShellProfile = 'unchanged (block exists)'
            } else {
                Add-Content -LiteralPath $prof -Value "`n$yoruBlockMarker`n" -Encoding utf8 -ErrorAction Stop
                Add-Content -LiteralPath $prof -Value $yoruText -Encoding utf8 -ErrorAction Stop
                Write-YoruOk 'Appended Yoru profile to $PROFILE'
                $script:Summary.PowerShellProfile = 'appended'
            }
        } else {
            Add-Content -LiteralPath $prof -Value "$yoruBlockMarker`n" -Encoding utf8 -ErrorAction Stop
            Add-Content -LiteralPath $prof -Value $yoruText -Encoding utf8 -ErrorAction Stop
            Write-YoruOk 'Created $PROFILE with Yoru profile'
            $script:Summary.PowerShellProfile = 'created'
        }
        Write-YoruNote $prof
    } catch {
        Write-Host "  [!] PowerShell profile: $($_.Exception.Message)" -ForegroundColor Red
        Write-AdminHint
        exit 1
    }

    # --- Fonts ---
    Write-YoruSection 'Fonts'
    $fontOk = Test-Yoru0xProtoFont
    if ($fontOk) {
        Write-YoruOk '0xProto Nerd Font Mono detected (HKLM/HKCU Fonts)'
        $script:Summary.Font = 'installed'
    } else {
        $script:Summary.Font = 'not installed'
        Write-Host '  [!] Font not installed: 0xProto Nerd Font Mono' -ForegroundColor Yellow
        Write-YoruNote 'Download: https://github.com/ryanoasis/nerd-fonts/releases'
        Write-YoruNote 'Install the font, set it in Windows Terminal if needed, then restart the terminal.'
        $null = Install-YoruFontFromNerdFonts
    }

    # --- Complete ---
    Write-YoruSection 'Complete'
    Write-Host '  ───────────────────────────' -ForegroundColor DarkRed
    Write-Host '  Deployment summary' -ForegroundColor Red
    Write-YoruNote "Theme: $($script:Summary.Theme)"
    $wtS = if ($script:Summary.TerminalSettings) { 'updated' } else { 'skipped' }
    $ffS = if ($script:Summary.Fastfetch) { 'updated' } else { 'skipped' }
    $stS = if ($script:Summary.Starship) { 'updated' } else { 'skipped' }
    Write-YoruNote "Windows Terminal settings: $wtS"
    Write-YoruNote "Fastfetch config + dragon: $ffS"
    Write-YoruNote "Starship config: $stS"
    Write-YoruNote "PowerShell profile: $($script:Summary.PowerShellProfile)"
    Write-YoruNote "Profile GUID source: $($script:Summary.GuidSource)"
    Write-YoruNote "Font: $($script:Summary.Font)"
    Write-Host ''
    Write-Host '  [done] Restart Windows Terminal to apply all changes.' -ForegroundColor Green
    Write-YoruNote 'If the dragon shows raw $1 tokens, logo type must be "file" in config.jsonc (already set in repo).'
    Write-Host ''
} catch {
    Write-Host "  [!] Unexpected failure: $($_.Exception.Message)" -ForegroundColor Red
    Write-AdminHint
    exit 1
}

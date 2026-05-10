#Requires -Version 5.1
<#
  Yoru Terminal — Sumi-e Crimson deployment (raw GitHub or local clone).
  irm https://raw.githubusercontent.com/tprojectzdev-sys/yoru-terminal/main/install.ps1 | iex

  Modes:
    (default)      Full install — dependencies + configs + profile
    -Minimal       Configs only (no winget installs)
    -Doctor        Diagnostics only
    -Restore       Restore latest install-time backup (*.yoru-backup-*.bak only)
    -Uninstall     Remove Yoru configs; restore WT from latest install backup; clean both standard profile paths
    -HardReset     Strip Yoru profile blocks (both standard paths) and delete WT settings.json (regenerates defaults)
#>
[CmdletBinding()]
param(
    [switch]$Full,
    [switch]$Minimal,
    [switch]$Doctor,
    [switch]$Restore,
    [switch]$Uninstall,
    [switch]$HardReset,
    [switch]$KeepWindowsTerminalSettingsOnUninstall
)

$ErrorActionPreference = 'Stop'

# --- repo / remote ---
$script:GitHubOwner = 'tprojectzdev-sys'
$script:GitHubRepo = 'yoru-terminal'
$script:GitHubBranch = 'main'
$script:RawBase = "https://raw.githubusercontent.com/$GitHubOwner/$GitHubRepo/$GitHubBranch"
$script:WinPowerShellWtGuid = '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}'
$script:YoruProfileBegin = '# YORU_TERMINAL_PROFILE_BLOCK'
$script:YoruProfileEnd = '# YORU_TERMINAL_PROFILE_BLOCK_END'
$script:YoruFastfetchMarker = 'yoru-terminal: bundled fastfetch config'
$script:YoruStarshipMarker = 'yoru-terminal: bundled starship config'

$script:LocalRepoRoot = $null
$script:UseLocalRepo = $false
if ($PSScriptRoot) {
    $candidate = Join-Path $PSScriptRoot 'terminal\settings.json'
    if (Test-Path -LiteralPath $candidate) {
        $script:LocalRepoRoot = $PSScriptRoot
        $script:UseLocalRepo = $true
    }
}

$script:Summary = [ordered]@{
    Theme             = 'Sumi-e Crimson'
    TerminalSettings  = $false
    Fastfetch         = $false
    Starship          = $false
    PowerShellProfile = 'unchanged'
    Font              = 'unknown'
    GuidSource        = ''
}

# --- mode resolution ---
$modeFlags = @(
    @{ Name = 'Full';    On = [bool]$Full },
    @{ Name = 'Minimal'; On = [bool]$Minimal },
    @{ Name = 'Doctor';  On = [bool]$Doctor },
    @{ Name = 'Restore'; On = [bool]$Restore },
    @{ Name = 'Uninstall'; On = [bool]$Uninstall },
    @{ Name = 'HardReset'; On = [bool]$HardReset }
)
$active = @($modeFlags | Where-Object { $_.On } | ForEach-Object { $_.Name })
if ($active.Count -gt 1) {
    Write-Host ''
    Write-Host '  [!] Use only one of: -Full, -Minimal, -Doctor, -Restore, -Uninstall, -HardReset' -ForegroundColor Red
    exit 1
}
$script:RunMode = if ($active.Count -eq 1) { $active[0] } else { 'Full' }

# --- helpers: output ---
function Get-IsAdmin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-AdminHint {
    if (-not (Get-IsAdmin)) {
        Write-Host '  Re-run as Administrator if this was a permission error.' -ForegroundColor Yellow
    }
}

function Write-YoruHeader {
    Write-Host ''
    Write-Host '  夜 Yoru Terminal — Installer' -ForegroundColor Red
    Write-Host '  Sumi-e Crimson deployment' -ForegroundColor DarkRed
    Write-Host '  ───────────────────────────' -ForegroundColor DarkRed
    if ($script:UseLocalRepo) {
        Write-YoruDim "  (local repo: $script:LocalRepoRoot)"
    }
    Write-Host ''
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

function Write-YoruWarn {
    param([string]$Message)
    Write-Host "  [warn] $Message" -ForegroundColor Yellow
}

function Write-YoruMissing {
    param([string]$Message)
    Write-Host "  [missing] $Message" -ForegroundColor DarkYellow
}

function Write-YoruFix {
    param([string]$Message)
    Write-Host "  [fix] $Message" -ForegroundColor Cyan
}

function Write-YoruDim {
    param([string]$Message)
    Write-Host "      $Message" -ForegroundColor DarkGray
}

# Subtle indeterminate progress (not flashy)
function Invoke-YoruWithProgress {
    param(
        [Parameter(Mandatory)][string]$Activity,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock
    )
    $id = 154321
    try {
        Write-Progress -Id $id -Activity 'Yoru' -Status $Activity -PercentComplete -1
        & $ScriptBlock
    } finally {
        Write-Progress -Id $id -Activity 'Yoru' -Completed
    }
}

function Wait-YoruJobWithSpinner {
    param(
        [Parameter(Mandatory)][System.Management.Automation.Job]$Job
    )
    $frames = @('\', '|', '/', '-')
    $i = 0
    while ($Job.State -eq 'Running') {
        $f = $frames[$i % $frames.Count]
        Write-Host "`r      $f  " -NoNewline -ForegroundColor DarkGray
        $i++
        Start-Sleep -Milliseconds 110
    }
    Write-Host "`r      "
}

function Invoke-YoruWebRequestFile {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$OutFile
    )
    $job = Start-Job -ScriptBlock {
        param($u, $o)
        $ErrorActionPreference = 'Stop'
        Invoke-WebRequest -Uri $u -OutFile $o -UseBasicParsing
    } -ArgumentList $Uri, $OutFile
    try {
        Wait-YoruJobWithSpinner -Job $job
        Receive-Job $job -Wait -ErrorAction Stop | Out-Null
        if ($job.JobStateInfo.State -ne 'Completed') {
            throw "Download failed (job state: $($job.JobStateInfo.State))"
        }
    } catch {
        throw "Download failed for '$Uri': $($_.Exception.Message)"
    } finally {
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-YoruWebRequestString {
    param([Parameter(Mandatory)][string]$Uri)
    $job = Start-Job -ScriptBlock {
        param($u)
        $ErrorActionPreference = 'Stop'
        (Invoke-WebRequest -Uri $u -UseBasicParsing).Content
    } -ArgumentList $Uri
    try {
        Wait-YoruJobWithSpinner -Job $job
        $content = Receive-Job $job -Wait -ErrorAction Stop
        if ($job.JobStateInfo.State -ne 'Completed') {
            throw "Download failed (job state: $($job.JobStateInfo.State))"
        }
        return [string]$content
    } catch {
        throw "Download failed for '$Uri': $($_.Exception.Message)"
    } finally {
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    }
}

function Test-YoruCommand {
    param([string]$Name)
    return [bool](Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue)
}

function Ensure-YoruDirectory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
    }
}

function New-YoruTimestampedBackup {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$Label,
        [ValidateSet('RestorePoint', 'Session', 'HardReset')]
        [string]$Kind = 'RestorePoint'
    )
    if (-not (Test-Path -LiteralPath $SourcePath)) {
        return $null
    }
    $dir = Split-Path -Parent $SourcePath
    $name = [System.IO.Path]::GetFileName($SourcePath)
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $tag = switch ($Kind) {
        'RestorePoint' { 'yoru-backup' }
        'Session' { 'yoru-session' }
        'HardReset' { 'yoru-hard-reset' }
    }
    $dest = Join-Path $dir "${name}.${tag}-${ts}.bak"
    Copy-Item -LiteralPath $SourcePath -Destination $dest -Force -ErrorAction Stop
    Write-YoruOk "$Label backup saved ($Kind)"
    Write-YoruDim $dest
    return $dest
}

function Get-YoruLatestBackup {
    param([Parameter(Mandatory)][string]$OriginalPath)
    if (-not $OriginalPath) { return $null }
    $dir = Split-Path -Parent $OriginalPath
    $name = [System.IO.Path]::GetFileName($OriginalPath)
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    # Only install-time restore points — excludes yoru-session / yoru-hard-reset so Restore/Uninstall are not confused by intermediate copies.
    Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "${name}.yoru-backup-*.bak" } |
        Sort-Object { $_.Name } -Descending |
        Select-Object -First 1
}

function Get-YoruStandardProfilePaths {
    $docs = [Environment]::GetFolderPath('MyDocuments')
    return @(
        (Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1'),
        (Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1')
    )
}

function Invoke-YoruGetTextFromRepo {
    param([Parameter(Mandatory)][string]$RepoRelativePath)
    $rel = $RepoRelativePath -replace '/', '\'
    if ($script:UseLocalRepo) {
        $p = Join-Path $script:LocalRepoRoot $rel
        if (-not (Test-Path -LiteralPath $p)) {
            throw "Local repo file missing: $p"
        }
        return Get-Content -LiteralPath $p -Raw -Encoding utf8
    }
    $uri = "$RawBase/$($RepoRelativePath -replace '\\', '/')"
    Write-YoruDim "fetching $RepoRelativePath"
    return Invoke-YoruWebRequestString -Uri $uri
}

function Invoke-YoruDownloadTo {
    param(
        [Parameter(Mandatory)][string]$RepoRelativePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )
    $destDir = Split-Path -Parent $DestinationPath
    Ensure-YoruDirectory -Path $destDir
    if ($script:UseLocalRepo) {
        $src = Join-Path $script:LocalRepoRoot ($RepoRelativePath -replace '/', '\')
        if (-not (Test-Path -LiteralPath $src)) {
            throw "Local repo file missing: $src"
        }
        Copy-Item -LiteralPath $src -Destination $DestinationPath -Force -ErrorAction Stop
        return
    }
    $uri = "$RawBase/$($RepoRelativePath -replace '\\', '/')"
    Write-YoruDim "fetching $RepoRelativePath"
    Invoke-YoruWebRequestFile -Uri $uri -OutFile $DestinationPath
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

function Get-YoruWtSettingsPath {
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
    return $wtSettings
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
            Write-YoruWarn "Font registry read skipped ($key): $($_.Exception.Message)"
        }
    }
    return $false
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
    Invoke-YoruWithProgress -Activity "Installing $DisplayName (winget)" {
        Install-WingetPackageSilently -PackageId $PackageId
    }
    Write-YoruOk $DisplayName
}

function Install-YoruFontFromNerdFonts {
    param()
    return $false
}

function Invoke-YoruDoctor {
    Write-YoruHeader
    Write-YoruSection 'Diagnostics'

    $wtPath = Get-YoruWtSettingsPath
    $wtDir = Split-Path -Parent $wtPath
    if (Test-Path -LiteralPath $wtDir) {
        Write-YoruOk "Windows Terminal LocalState found"
        Write-YoruDim $wtDir
    } else {
        Write-YoruMissing 'Windows Terminal LocalState not found (install Windows Terminal from the Store)'
        Write-YoruFix 'Install Windows Terminal, open it once, then run: .\install.ps1 -Doctor'
    }

    $psVer = $PSVersionTable.PSVersion.ToString()
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Write-YoruOk "PowerShell $psVer"
    } else {
        Write-YoruWarn "PowerShell $psVer (Yoru targets PowerShell 7+; installer can install it with winget)"
        Write-YoruFix '.\install.ps1 -Full   or   winget install Microsoft.PowerShell'
    }

    if (Test-YoruCommand 'fastfetch') {
        Write-YoruOk 'fastfetch on PATH'
    } else {
        Write-YoruMissing 'fastfetch not found'
        Write-YoruFix '.\install.ps1 -Full   or   winget install Fastfetch-cli.Fastfetch'
    }

    if (Test-YoruCommand 'starship') {
        Write-YoruOk 'starship on PATH'
    } else {
        Write-YoruMissing 'starship not found'
        Write-YoruFix '.\install.ps1 -Full   or   winget install Starship.Starship'
    }

    if (Test-Yoru0xProtoFont) {
        Write-YoruOk '0xProto Nerd Font Mono detected (Fonts registry)'
    } else {
        Write-YoruMissing '0xProto Nerd Font Mono not detected'
        Write-YoruFix 'https://github.com/ryanoasis/nerd-fonts/releases — install 0xProto Nerd Font Mono'
    }

    $ffCfg = Join-Path $HOME '.config\fastfetch\config.jsonc'
    $ffDragon = Join-Path $HOME '.config\fastfetch\dragon.txt'
    if (Test-Path -LiteralPath $ffCfg) {
        Write-YoruOk "fastfetch config exists"
        Write-YoruDim $ffCfg
    } else {
        Write-YoruMissing 'fastfetch config.jsonc missing'
        Write-YoruFix '.\install.ps1 -Full or -Minimal'
    }
    if (Test-Path -LiteralPath $ffDragon) {
        Write-YoruOk 'dragon ASCII file exists'
        Write-YoruDim $ffDragon
    } else {
        Write-YoruMissing 'dragon.txt missing'
        Write-YoruFix '.\install.ps1 -Full or -Minimal'
    }

    $starshipCfg = Join-Path $HOME '.config\starship\starship.toml'
    if (Test-Path -LiteralPath $starshipCfg) {
        Write-YoruOk 'starship config exists'
        Write-YoruDim $starshipCfg
    } else {
        Write-YoruMissing 'starship.toml missing'
        Write-YoruFix '.\install.ps1 -Full or -Minimal'
    }

    if (Test-Path -LiteralPath $wtPath) {
        Write-YoruOk 'Windows Terminal settings.json exists'
        Write-YoruDim $wtPath
        $raw = Get-Content -LiteralPath $wtPath -Raw -ErrorAction SilentlyContinue
        if ($raw -and $raw.Contains('{powershell-guid}')) {
            Write-YoruWarn 'Placeholder {powershell-guid} still present in settings.json — run installer to replace'
            Write-YoruFix '.\install.ps1 -Full or -Minimal'
        }
    } else {
        Write-YoruMissing 'settings.json missing (first launch or wrong path)'
    }

    $prof = $PROFILE
    if ($prof -and (Test-Path -LiteralPath $prof)) {
        Write-YoruOk 'PowerShell profile exists'
        Write-YoruDim $prof
        $pr = Get-Content -LiteralPath $prof -Raw -ErrorAction SilentlyContinue
        if ($pr -and $pr.Contains($script:YoruProfileBegin)) {
            Write-YoruOk 'Yoru profile block is present'
        } else {
            Write-YoruMissing 'Yoru profile block not found in $PROFILE'
            Write-YoruFix '.\install.ps1 -Full or -Minimal'
        }
    } elseif ($prof) {
        Write-YoruMissing 'PowerShell profile file not created yet'
        Write-YoruDim $prof
    } else {
        Write-YoruMissing '$PROFILE is empty for this host'
    }

    if ($env:WT_SESSION) {
        Write-YoruOk 'Running inside Windows Terminal (WT_SESSION set)'
    } else {
        Write-YoruWarn 'Not running in Windows Terminal (or WT_SESSION unset) — classic console may limit visuals'
        Write-YoruFix 'Open Windows Terminal and run: .\install.ps1 -Doctor'
    }

    if (-not (Test-WingetAvailable)) {
        Write-YoruMissing 'winget not available (App Installer / Microsoft Store)'
        Write-YoruFix 'Install App Installer from the Store for -Full installs'
    } else {
        Write-YoruOk 'winget available'
    }

    Write-Host ''
    Write-YoruDim 'Next: fix any [missing] lines, then run .\install.ps1 -Full (or -Minimal if tools already installed).'
    Write-YoruDim 'Backups: see README (Safety / Backups). Restore uses *.yoru-backup-*.bak only.'
    Write-Host ''
}

function Invoke-YoruRestore {
    Write-YoruHeader
    Write-YoruSection 'Restore from backups'

    $wtPath = Get-YoruWtSettingsPath
    $wtBackup = Get-YoruLatestBackup -OriginalPath $wtPath
    if (-not $wtBackup) {
        Write-YoruWarn 'No install-time backup for Windows Terminal (expected: settings.json.yoru-backup-*.bak next to settings.json)'
    } else {
        if (Test-Path -LiteralPath $wtPath) {
            $null = New-YoruTimestampedBackup -SourcePath $wtPath -Label 'Windows Terminal settings.json (pre-restore)' -Kind Session
        }
        Copy-Item -LiteralPath $wtBackup.FullName -Destination $wtPath -Force -ErrorAction Stop
        Write-YoruOk "Restored Windows Terminal settings from:"
        Write-YoruDim $wtBackup.FullName
    }

    Write-YoruSection 'PowerShell profiles (standard paths)'
    $profRestoredAny = $false
    foreach ($profPath in (Get-YoruStandardProfilePaths)) {
        $profBackup = Get-YoruLatestBackup -OriginalPath $profPath
        if (-not $profBackup) {
            Write-YoruDim "no install-time backup next to: $profPath"
            continue
        }
        if (Test-Path -LiteralPath $profPath) {
            $null = New-YoruTimestampedBackup -SourcePath $profPath -Label 'PowerShell profile (pre-restore)' -Kind Session
        } else {
            Ensure-YoruDirectory -Path (Split-Path -Parent $profPath)
        }
        Copy-Item -LiteralPath $profBackup.FullName -Destination $profPath -Force -ErrorAction Stop
        Write-YoruOk 'Restored PowerShell profile from:'
        Write-YoruDim $profBackup.FullName
        $profRestoredAny = $true
    }
    if (-not $profRestoredAny) {
        Write-YoruWarn 'No install-time backup (*.yoru-backup-*.bak) beside either standard profile path.'
    }

    if (-not $wtBackup -and -not $profRestoredAny) {
        Write-Host ''
        Write-Host '  [!] Nothing restored — no install-time backups (*.yoru-backup-*.bak) found.' -ForegroundColor Yellow
        Write-YoruDim 'Install once to create restore points, use -HardReset snapshots manually, or copy a .bak file yourself.'
        exit 2
    }

    Write-Host ''
    Write-YoruOk 'Restore finished. Close all terminal windows, then reopen Windows Terminal.'
    Write-Host ''
}

function Remove-YoruProfileBlock {
    param([Parameter(Mandatory)][string]$ProfilePath)
    $raw = Get-Content -LiteralPath $ProfilePath -Raw -ErrorAction Stop
    if ([string]::IsNullOrEmpty($raw)) {
        return $false
    }

    $i = $raw.IndexOf($script:YoruProfileBegin, [System.StringComparison]::Ordinal)
    if ($i -lt 0) {
        return $false
    }

    # Drop a single preceding newline (LF or CRLF) so we do not leave a stray blank line.
    $cutStart = $i
    if ($cutStart -gt 0) {
        $prev = $cutStart - 1
        if ($raw[$prev] -eq [char]10) {
            $cutStart = $prev
            if ($cutStart -gt 0 -and $raw[$cutStart - 1] -eq [char]13) {
                $cutStart--
            }
        } elseif ($raw[$prev] -eq [char]13) {
            $cutStart = $prev
        }
    }

    $afterBegin = $i + $script:YoruProfileBegin.Length
    if ($afterBegin -gt $raw.Length) {
        $afterBegin = $raw.Length
    }

    $endIdx = $raw.IndexOf($script:YoruProfileEnd, $afterBegin, [System.StringComparison]::Ordinal)
    if ($endIdx -ge 0) {
        $j = $endIdx + $script:YoruProfileEnd.Length
        while ($j -lt $raw.Length) {
            $ch = $raw[$j]
            if ($ch -eq [char]13 -or $ch -eq [char]10) { $j++ } else { break }
        }
    } else {
        Write-YoruWarn 'Legacy Yoru profile: BEGIN marker found but END marker is missing — removing from BEGIN through end of file.'
        $j = $raw.Length
    }

    if ($j -lt 0) { $j = 0 }
    if ($j -gt $raw.Length) { $j = $raw.Length }
    if ($cutStart -lt 0) { $cutStart = 0 }
    if ($cutStart -gt $raw.Length) { $cutStart = $raw.Length }

    $newText = $raw.Substring(0, $cutStart)
    if ($j -lt $raw.Length) {
        $newText += $raw.Substring($j)
    }
    $newText = $newText.TrimEnd()

    if ([string]::IsNullOrWhiteSpace($newText)) {
        Remove-Item -LiteralPath $ProfilePath -Force -ErrorAction Stop
        return $true
    }
    Set-Content -LiteralPath $ProfilePath -Value $newText -Encoding utf8 -NoNewline -ErrorAction Stop
    return $true
}

function Invoke-YoruHardReset {
    Write-YoruHeader
    Write-YoruSection 'Hard reset'
    Write-YoruDim 'Removes Yoru profile blocks from both standard locations, deletes Windows Terminal settings.json (defaults regenerate).'
    Write-YoruDim 'Does not remove PowerShell, Windows Terminal, fastfetch, starship, or fonts. Backups use *.yoru-hard-reset-*.bak (ignored by -Restore).'
    Write-Host ''

    Write-YoruSection 'PowerShell profiles'
    foreach ($p in (Get-YoruStandardProfilePaths)) {
        if (-not (Test-Path -LiteralPath $p)) {
            Write-YoruMissing "not present: $p"
            continue
        }
        $null = New-YoruTimestampedBackup -SourcePath $p -Label "Profile (pre-hard-reset)" -Kind HardReset
        $raw = Get-Content -LiteralPath $p -Raw -ErrorAction SilentlyContinue
        if (-not $raw -or -not $raw.Contains($script:YoruProfileBegin)) {
            Write-YoruOk "no Yoru block: $p"
            continue
        }
        if (Remove-YoruProfileBlock -ProfilePath $p) {
            if (Test-Path -LiteralPath $p) {
                Write-YoruOk "removed Yoru block: $p"
            } else {
                Write-YoruOk "removed empty profile file: $p"
            }
        }
        if (Test-Path -LiteralPath $p) {
            Write-YoruProfileResidualWarnings -ProfilePath $p
        }
    }

    Write-YoruSection 'Windows Terminal'
    $pkgs = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'Microsoft.WindowsTerminal*' }
    if (-not $pkgs) {
        Write-YoruMissing 'No Microsoft.WindowsTerminal* package folders under LocalAppData\Packages'
    } else {
        foreach ($pkg in $pkgs) {
            $settings = Join-Path $pkg.FullName 'LocalState\settings.json'
            if (-not (Test-Path -LiteralPath $settings)) {
                Write-YoruDim "no settings.json: $settings"
                continue
            }
            $null = New-YoruTimestampedBackup -SourcePath $settings -Label "Windows Terminal settings ($($pkg.Name))" -Kind HardReset
            Remove-Item -LiteralPath $settings -Force -ErrorAction Stop
            Write-YoruOk 'Removed settings.json (Terminal will recreate defaults on next launch)'
            Write-YoruDim $settings
        }
    }

    Write-Host ''
    Write-YoruOk 'Hard reset finished. Close all terminal windows, then reopen Windows Terminal.'
    Write-Host ''
}

function Write-YoruProfileResidualWarnings {
    param([Parameter(Mandatory)][string]$ProfilePath)
    if (-not (Test-Path -LiteralPath $ProfilePath)) {
        return
    }
    $t = Get-Content -LiteralPath $ProfilePath -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($t)) {
        return
    }

    $found = @()
    if ($t.Contains($script:YoruProfileBegin)) {
        $found += '# YORU_TERMINAL_PROFILE_BLOCK'
    }
    if ($t.Contains($script:YoruProfileEnd)) {
        $found += '# YORU_TERMINAL_PROFILE_BLOCK_END'
    }
    if ($t -match '(?i)starship\s+init\s+powershell') {
        $found += 'starship init powershell'
    }
    if ($t -match '(?i)fastfetch[^\r\n]*--config') {
        $found += 'fastfetch --config'
    }

    foreach ($item in ($found | Select-Object -Unique)) {
        Write-YoruWarn "Profile still contains '$item'. If you did not add this outside Yoru, edit '$ProfilePath' or restore from a '*.yoru-backup-*.bak' file next to your profile."
    }
}

function Invoke-YoruUninstall {
    Write-YoruHeader
    Write-YoruSection 'Uninstall Yoru Terminal changes'

    $skipped = [System.Collections.Generic.List[string]]::new()

    $ffCfg = Join-Path $HOME '.config\fastfetch\config.jsonc'
    $ffDragon = Join-Path $HOME '.config\fastfetch\dragon.txt'
    if (Test-Path -LiteralPath $ffCfg) {
        $txt = Get-Content -LiteralPath $ffCfg -Raw -ErrorAction SilentlyContinue
        if ($txt -and $txt.Contains($script:YoruFastfetchMarker)) {
            Remove-Item -LiteralPath $ffCfg -Force -ErrorAction Stop
            Write-YoruOk 'Removed fastfetch config.jsonc (Yoru marker)'
            if (Test-Path -LiteralPath $ffDragon) {
                Remove-Item -LiteralPath $ffDragon -Force -ErrorAction Stop
                Write-YoruOk 'Removed fastfetch dragon.txt'
            }
        } else {
            $skipped.Add('fastfetch config.jsonc (no Yoru marker — left untouched)')
        }
    } else {
        $skipped.Add('fastfetch config.jsonc (not present)')
    }

    $starshipCfg = Join-Path $HOME '.config\starship\starship.toml'
    if (Test-Path -LiteralPath $starshipCfg) {
        $st = Get-Content -LiteralPath $starshipCfg -Raw -ErrorAction SilentlyContinue
        if ($st -and $st.Contains($script:YoruStarshipMarker)) {
            Remove-Item -LiteralPath $starshipCfg -Force -ErrorAction Stop
            Write-YoruOk 'Removed starship.toml (Yoru marker)'
        } else {
            $skipped.Add('starship.toml (no Yoru marker — left untouched)')
        }
    } else {
        $skipped.Add('starship.toml (not present)')
    }

    Write-YoruSection 'PowerShell profiles (both standard paths)'
    foreach ($prof in (Get-YoruStandardProfilePaths)) {
        if (-not (Test-Path -LiteralPath $prof)) {
            Write-YoruDim "not present: $prof"
            continue
        }
        $null = New-YoruTimestampedBackup -SourcePath $prof -Label 'PowerShell profile (pre-uninstall)' -Kind Session
        if (Remove-YoruProfileBlock -ProfilePath $prof) {
            Write-YoruOk "Removed Yoru block: $prof"
        } else {
            Write-YoruDim "no Yoru block: $prof"
        }
        if (Test-Path -LiteralPath $prof) {
            Write-YoruProfileResidualWarnings -ProfilePath $prof
        }
    }

    $wtPath = Get-YoruWtSettingsPath
    if (-not $KeepWindowsTerminalSettingsOnUninstall) {
        $b = Get-YoruLatestBackup -OriginalPath $wtPath
        if ($b -and (Test-Path -LiteralPath $wtPath)) {
            $null = New-YoruTimestampedBackup -SourcePath $wtPath -Label 'Windows Terminal settings (pre-uninstall)' -Kind Session
            Copy-Item -LiteralPath $b.FullName -Destination $wtPath -Force -ErrorAction Stop
            Write-YoruOk 'Windows Terminal settings restored from latest Yoru backup'
            Write-YoruDim $b.FullName
        } elseif (-not $b) {
            $skipped.Add('Windows Terminal settings: no Yoru backup to restore (left as-is)')
        }
    } else {
        $skipped.Add('Windows Terminal settings kept (-KeepWindowsTerminalSettingsOnUninstall)')
    }

    Write-YoruSection 'Notes'
    foreach ($s in $skipped) {
        Write-YoruDim $s
    }

    Write-Host ''
    Write-YoruDim 'Left untouched: PowerShell 7, fastfetch, starship, winget packages, and fonts (not removed).'
    Write-YoruDim 'Close all terminals, then reopen Windows Terminal.'
    Write-Host ''
}

function Install-YoruCore {
    param([switch]$SkipWinget)

    if ($SkipWinget) {
        Write-YoruSection 'Core (minimal — skipped winget)'
        if (-not (Test-WingetAvailable)) {
            Write-YoruWarn 'winget not found — cannot auto-install tools in Full mode; Minimal skips installs.'
        }
        return $false
    }

    Write-YoruSection 'Core'
    if (-not (Test-WingetAvailable)) {
        Write-Host '  [!] winget not found. Install App Installer from the Microsoft Store, then re-run.' -ForegroundColor Red
        Write-YoruFix 'Or run: .\install.ps1 -Minimal if dependencies are already installed.'
        exit 1
    }

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
            Invoke-YoruWithProgress -Activity 'Installing PowerShell 7 (winget)' {
                Install-WingetPackageSilently -PackageId 'Microsoft.PowerShell'
            }
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
        Write-YoruWarn 'PowerShell 7 was just installed. Close every terminal, reopen Windows Terminal,'
        Write-YoruDim 'add or select a PowerShell 7 tab once, then run this installer again so we can match its profile GUID.'
        Write-Host ''
    }

    return $pwshInstalledNow
}

function Install-YoruAssetsAndTerminal {
    param()

    Write-YoruSection 'Assets'
    $fastfetchDir = Join-Path $HOME '.config\fastfetch'
    $starshipDir = Join-Path $HOME '.config\starship'
    try {
        Ensure-YoruDirectory -Path $fastfetchDir
        Ensure-YoruDirectory -Path $starshipDir
    } catch {
        Write-Host "  [!] Config folders: $($_.Exception.Message)" -ForegroundColor Red
        Write-AdminHint
        exit 1
    }

    try {
        Invoke-YoruDownloadTo -RepoRelativePath 'fastfetch/dragon.txt' -DestinationPath (Join-Path $fastfetchDir 'dragon.txt')
        Write-YoruOk 'fastfetch/dragon.txt'
        $script:Summary.Fastfetch = $true
    } catch {
        Write-Host "  [!] $($_.Exception.Message)" -ForegroundColor Red
        Write-AdminHint
        exit 1
    }

    try {
        Invoke-YoruDownloadTo -RepoRelativePath 'fastfetch/config.jsonc' -DestinationPath (Join-Path $fastfetchDir 'config.jsonc')
        Write-YoruOk 'fastfetch/config.jsonc'
    } catch {
        Write-Host "  [!] $($_.Exception.Message)" -ForegroundColor Red
        Write-AdminHint
        exit 1
    }

    try {
        Invoke-YoruDownloadTo -RepoRelativePath 'starship/starship.toml' -DestinationPath (Join-Path $starshipDir 'starship.toml')
        Write-YoruOk 'starship/starship.toml'
        $script:Summary.Starship = $true
    } catch {
        Write-Host "  [!] $($_.Exception.Message)" -ForegroundColor Red
        Write-AdminHint
        exit 1
    }

    Write-YoruSection 'Terminal'
    $wtSettings = Get-YoruWtSettingsPath
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
            Write-YoruDim 'No existing settings.json (first run).'
        }

        $settingsRaw = Invoke-YoruGetTextFromRepo -RepoRelativePath 'terminal/settings.json'
        $settingsOut = Apply-YoruTerminalSettingsText -Content $settingsRaw -PsGuid $guidInfo.Guid -UseWindowsPowerShellFallback $useWinPs
        Set-Content -LiteralPath $wtSettings -Value $settingsOut -Encoding utf8 -ErrorAction Stop
        Write-YoruOk 'terminal/settings.json deployed'
        $script:Summary.TerminalSettings = $true

        Write-YoruDim "defaultProfile GUID: $($guidInfo.Guid)"
        Write-YoruDim "detection: $($guidInfo.Source)"
        if ($guidInfo.Guid -notmatch '^\{[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}$') {
            Write-YoruWarn 'GUID format unexpected — confirm defaultProfile in Windows Terminal → Settings → JSON.'
        }
    } catch {
        Write-Host "  [!] Windows Terminal: $($_.Exception.Message)" -ForegroundColor Red
        Write-AdminHint
        exit 1
    }
}

function Install-YoruPowerShellProfile {
    Write-YoruSection 'PowerShell'
    $prof = $PROFILE
    if (-not $prof) {
        Write-Host '  [!] `$PROFILE is empty; cannot append Yoru profile.' -ForegroundColor Red
        exit 1
    }
    $profDir = Split-Path -Parent $prof
    try {
        Ensure-YoruDirectory -Path $profDir
        if (Test-Path -LiteralPath $prof) {
            $null = New-YoruTimestampedBackup -SourcePath $prof -Label 'PowerShell profile'
        }

        $yoruText = Invoke-YoruGetTextFromRepo -RepoRelativePath 'powershell/profile.ps1'
        if (Test-Path -LiteralPath $prof) {
            $existing = Get-Content -LiteralPath $prof -Raw -ErrorAction Stop
            if ($existing -and $existing.Contains($script:YoruProfileBegin)) {
                $bIdx = $existing.IndexOf($script:YoruProfileBegin, [System.StringComparison]::Ordinal)
                $afterBegin = [Math]::Min($bIdx + $script:YoruProfileBegin.Length, $existing.Length)
                $eIdx = $existing.IndexOf($script:YoruProfileEnd, $afterBegin, [System.StringComparison]::Ordinal)
                if ($eIdx -lt 0) {
                    Write-YoruWarn 'Legacy Yoru profile (BEGIN without END). Appending END marker so uninstall can find the block.'
                    Add-Content -LiteralPath $prof -Value "`n$($script:YoruProfileEnd)`n" -Encoding utf8 -ErrorAction Stop
                    $script:Summary.PowerShellProfile = 'repaired (END marker appended)'
                } else {
                    Write-YoruOk 'Yoru profile block already present (skipped append)'
                    $script:Summary.PowerShellProfile = 'unchanged (block exists)'
                }
            } else {
                Add-Content -LiteralPath $prof -Value "`n$($script:YoruProfileBegin)`n" -Encoding utf8 -ErrorAction Stop
                Add-Content -LiteralPath $prof -Value $yoruText -Encoding utf8 -ErrorAction Stop
                Write-YoruOk 'Appended Yoru profile to $PROFILE'
                $script:Summary.PowerShellProfile = 'appended'
            }
        } else {
            Add-Content -LiteralPath $prof -Value "$($script:YoruProfileBegin)`n" -Encoding utf8 -ErrorAction Stop
            Add-Content -LiteralPath $prof -Value $yoruText -Encoding utf8 -ErrorAction Stop
            Write-YoruOk 'Created $PROFILE with Yoru profile'
            $script:Summary.PowerShellProfile = 'created'
        }
        Write-YoruDim $prof
    } catch {
        Write-Host "  [!] PowerShell profile: $($_.Exception.Message)" -ForegroundColor Red
        Write-AdminHint
        exit 1
    }
}

function Install-YoruFontsSection {
    Write-YoruSection 'Fonts'
    $fontOk = Test-Yoru0xProtoFont
    if ($fontOk) {
        Write-YoruOk '0xProto Nerd Font Mono detected (HKLM/HKCU Fonts)'
        $script:Summary.Font = 'installed'
    } else {
        $script:Summary.Font = 'not installed'
        Write-YoruWarn 'Font not installed: 0xProto Nerd Font Mono'
        Write-YoruDim 'Download: https://github.com/ryanoasis/nerd-fonts/releases'
        Write-YoruDim 'Install the font, set it in Windows Terminal if needed, then restart the terminal.'
        $null = Install-YoruFontFromNerdFonts
    }
}

function Write-YoruFinalSummary {
    Write-YoruSection 'Complete'
    Write-Host '  ───────────────────────────' -ForegroundColor DarkRed
    Write-Host '  Deployment summary' -ForegroundColor Red
    Write-YoruDim "Theme: $($script:Summary.Theme)"
    $wtS = if ($script:Summary.TerminalSettings) { 'updated' } else { 'skipped' }
    $ffS = if ($script:Summary.Fastfetch) { 'updated' } else { 'skipped' }
    $stS = if ($script:Summary.Starship) { 'updated' } else { 'skipped' }
    Write-YoruDim "Windows Terminal settings: $wtS"
    Write-YoruDim "Fastfetch config + dragon: $ffS"
    Write-YoruDim "Starship config: $stS"
    Write-YoruDim "PowerShell profile: $($script:Summary.PowerShellProfile)"
    Write-YoruDim "Profile GUID source: $($script:Summary.GuidSource)"
    Write-YoruDim "Font: $($script:Summary.Font)"
    Write-Host ''
    Write-Host '  [done] Close all terminal windows, then reopen Windows Terminal.' -ForegroundColor Green
    Write-YoruDim 'If the dragon shows raw `$1 tokens, logo type must be "file" in config.jsonc (already set in repo).'
    Write-Host ''
}

# --- dispatch ---
try {
    switch ($script:RunMode) {
        'Doctor' {
            Invoke-YoruDoctor
            return
        }
        'Restore' {
            Invoke-YoruRestore
            return
        }
        'Uninstall' {
            Invoke-YoruUninstall
            return
        }
        'HardReset' {
            Invoke-YoruHardReset
            return
        }
        'Minimal' {
            Write-YoruHeader
            Write-YoruSection 'Mode'
            Write-YoruDim 'Minimal: configs only (no winget dependency installs).'
            if (-not (Test-YoruCommand 'fastfetch')) { Write-YoruWarn 'fastfetch not on PATH — install or use -Full.' }
            if (-not (Test-YoruCommand 'starship')) { Write-YoruWarn 'starship not on PATH — install or use -Full.' }
            Install-YoruAssetsAndTerminal
            Install-YoruPowerShellProfile
            Install-YoruFontsSection
            Write-YoruFinalSummary
            return
        }
        default {
            # Full (explicit or default)
            Write-YoruHeader
            if ($Full) {
                Write-YoruSection 'Mode'
                Write-YoruDim 'Full: dependencies + configs + profile.'
            }
            $null = Install-YoruCore -SkipWinget:$false
            Install-YoruAssetsAndTerminal
            Install-YoruPowerShellProfile
            Install-YoruFontsSection
            Write-YoruFinalSummary
            return
        }
    }
} catch {
    Write-Host "  [!] Unexpected failure: $($_.Exception.Message)" -ForegroundColor Red
    Write-AdminHint
    exit 1
}

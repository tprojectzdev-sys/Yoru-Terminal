# Yoru Terminal — PowerShell Profile
# Part of github.com/tprojectzdev-sys/yoru-terminal
# Edit STARSHIP_CONFIG and fastfetch path if your setup differs

Clear-Host

$env:STARSHIP_CONFIG = Join-Path $HOME '.config\starship\starship.toml'
if (Get-Command starship -CommandType Application -ErrorAction SilentlyContinue) {
    Invoke-Expression (& starship init powershell)
}

function ll { Get-ChildItem -Force @args }
function touch { New-Item -ItemType File -Path @args }
Set-Alias -Name which -Value Get-Command
function reload { . $PROFILE }

$runFastfetch =
    [Environment]::UserInteractive -and
    $Host.Name -eq 'ConsoleHost' -and
    $env:TERM_PROGRAM -ne 'vscode' -and
    (Get-Command fastfetch -CommandType Application -ErrorAction SilentlyContinue)

if ($runFastfetch) {
    $ffConfig = Join-Path $HOME '.config\fastfetch\config.jsonc'
    & fastfetch --config $ffConfig
}

# YORU_TERMINAL_PROFILE_BLOCK_END

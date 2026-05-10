#Requires -Version 5.1
# Remove Yoru-specific files/blocks; optionally keep current Windows Terminal JSON.
param(
    [switch]$KeepWindowsTerminalSettingsOnUninstall
)
$here = $PSScriptRoot
& (Join-Path $here 'install.ps1') -Uninstall -KeepWindowsTerminalSettingsOnUninstall:$KeepWindowsTerminalSettingsOnUninstall

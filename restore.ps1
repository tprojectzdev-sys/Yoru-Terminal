#Requires -Version 5.1
# Restore latest Yoru timestamped backups (Windows Terminal + PowerShell profile).
param()
$here = $PSScriptRoot
& (Join-Path $here 'install.ps1') -Restore

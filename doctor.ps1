#Requires -Version 5.1
# Thin wrapper — run diagnostics without remembering install.ps1 switches.
param()
$here = $PSScriptRoot
& (Join-Path $here 'install.ps1') -Doctor

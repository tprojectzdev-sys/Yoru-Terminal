#Requires -Version 5.1
# Hard reset: strip Yoru profile blocks (both Documents paths) and delete WT settings.json (defaults regenerate).
param()
$here = $PSScriptRoot
& (Join-Path $here 'install.ps1') -HardReset

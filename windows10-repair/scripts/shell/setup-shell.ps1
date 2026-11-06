. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Common.ps1')
$ErrorActionPreference = 'Stop'
$PSVersionTable
Expand-Archive -LiteralPath "$RepairPayload\Terminal-Preinstall.zip" -DestinationPath "$RepairPayload\Terminal-Package" -Force
Get-ChildItem "$RepairPayload\Terminal-Package" -Recurse | Select-Object FullName

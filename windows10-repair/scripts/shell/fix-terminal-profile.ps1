. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Common.ps1')
$ErrorActionPreference = 'Stop'
$path = "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
$pwsh = "$RepairPayload\PowerShell\PowerShell\7\pwsh.exe"
if (!(Test-Path $pwsh)) { throw 'PowerShell 7 executable missing' }
Copy-Item -LiteralPath $path -Destination "$path.backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
$settings = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
$profile = $settings.profiles.list | Where-Object guid -eq '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}'
$profile.name = 'PowerShell 7'
$profile.commandline = '"' + $pwsh + '"'
$settings.defaultProfile = $profile.guid
$settings | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $path -Encoding utf8
$check = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
$check.profiles.list | Where-Object guid -eq $check.defaultProfile | Format-List name,commandline
& $pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'

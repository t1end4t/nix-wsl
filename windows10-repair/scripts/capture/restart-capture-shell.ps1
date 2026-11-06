. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Common.ps1')
$ErrorActionPreference = 'Stop'
$shellPath = 'C:\Windows\SystemApps\ShellExperienceHost_cw5n1h2txyewy\ShellExperienceHost.exe'
if (-not (Test-Path -LiteralPath $shellPath)) { throw 'ShellExperienceHost executable not accessible; nothing changed.' }
$captureShell = Get-Process ShellExperienceHost -ErrorAction SilentlyContinue
if ($captureShell) {
 $captureShell | Stop-Process -ErrorAction Stop
 'Stopped ShellExperienceHost.'
 Start-Sleep -Seconds 2
}
if (-not (Get-Process ShellExperienceHost -ErrorAction SilentlyContinue)) {
 Start-Process -FilePath $shellPath -WindowStyle Hidden -ErrorAction Stop
 Start-Sleep -Seconds 2
}
Get-Process ShellExperienceHost -ErrorAction Stop | Select-Object ProcessName,Id,Responding | Format-List

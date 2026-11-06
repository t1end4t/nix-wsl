. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Common.ps1')
$ErrorActionPreference = 'Stop'
$currentSession = (Get-Process -Id $PID).SessionId
$desktopShell = Get-Process explorer -ErrorAction SilentlyContinue | Where-Object SessionId -eq $currentSession
if ($desktopShell) { $desktopShell | Stop-Process -ErrorAction Stop; 'Explorer restarted for current session.' }
Start-Sleep -Seconds 2
if (-not (Get-Process explorer -ErrorAction SilentlyContinue | Where-Object SessionId -eq $currentSession)) {
 Start-Process 'C:\Windows\explorer.exe' -WindowStyle Hidden
 Start-Sleep -Seconds 3
}
Get-Process explorer,ShellExperienceHost -ErrorAction SilentlyContinue | Select-Object ProcessName,Id,Responding | Format-List

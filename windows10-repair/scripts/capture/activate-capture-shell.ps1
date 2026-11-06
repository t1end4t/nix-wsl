. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Common.ps1')
$ErrorActionPreference = 'Stop'
Start-Process -FilePath 'C:\Windows\explorer.exe' -ArgumentList 'shell:AppsFolder\Microsoft.Windows.ShellExperienceHost_cw5n1h2txyewy!App' -WindowStyle Hidden
Start-Sleep -Seconds 3
Get-Process ShellExperienceHost -ErrorAction SilentlyContinue | Select-Object ProcessName,Id,Responding | Format-List
try {
 Start-Process 'ms-screenclip:' -ErrorAction Stop
 'Capture protocol launch requested.'
} catch { 'Capture protocol activation failed: ' + $_.Exception.Message }
Start-Sleep -Seconds 2
Get-Process ShellExperienceHost -ErrorAction SilentlyContinue | Select-Object ProcessName,Id,Responding | Format-List

. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Common.ps1')
$ErrorActionPreference = 'Continue'
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' | Select-Object ProductName,DisplayVersion,ReleaseId,CurrentBuild,UBR
Get-ChildItem 'C:\Program Files\WindowsApps' -Directory -ErrorAction SilentlyContinue | Where-Object Name -match 'WindowsStore|DesktopAppInstaller|OpenAI|ChatGPT' | Select-Object Name
Test-Path 'C:\Windows\System32\AppxPackaging.dll'
Test-Path 'C:\Windows\System32\AppXDeploymentClient.dll'
Get-ChildItem C:\Windows\System32\WindowsPowerShell -ErrorAction SilentlyContinue
Get-Service AppXSvc,ClipSVC,InstallService,wuauserv,BITS -ErrorAction Continue | Select-Object Name,Status,StartType

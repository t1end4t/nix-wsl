. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Common.ps1')
$ErrorActionPreference = 'Stop'
$shellDir = "$RepairPayload\PowerShell\PowerShell\7"
$userPath = [Environment]::GetEnvironmentVariable('Path','User')
if (($userPath -split ';') -notcontains $shellDir) { [Environment]::SetEnvironmentVariable('Path', "$userPath;$shellDir", 'User') }
$ws = New-Object -ComObject WScript.Shell
$link = $ws.CreateShortcut("$([Environment]::GetFolderPath('Programs'))\PowerShell 7.lnk")
$link.TargetPath = "$shellDir\pwsh.exe"
$link.WorkingDirectory = $HOME
$link.Save()
Get-Module -ListAvailable Appx
Import-Module Appx -SkipEditionCheck
$dep = (Get-ChildItem "$RepairPayload\Terminal-Package\*x64*.appx").FullName
$bundle = (Get-ChildItem "$RepairPayload\Terminal-Package\*.msixbundle").FullName
Add-AppxPackage -Path $dep
Add-AppxPackage -Path $bundle
Get-AppxPackage Microsoft.WindowsTerminal | Select-Object Name,Version,InstallLocation

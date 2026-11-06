. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Common.ps1')
$ErrorActionPreference = 'Stop'
$dest = "$RepairPayload\WindowsTerminal"
[xml]$manifest = Get-Content "$dest\AppxManifest.xml"
$manifest.Package.Dependencies | Format-List
$proc = Start-Process "$dest\WindowsTerminal.exe" -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 3
if ($proc.HasExited) { Write-Output "Terminal exited: $($proc.ExitCode)" } else { Write-Output "Terminal running PID: $($proc.Id)" }
$ws = New-Object -ComObject WScript.Shell
$link = $ws.CreateShortcut("$([Environment]::GetFolderPath('Programs'))\Windows Terminal.lnk")
$link.TargetPath = "$dest\WindowsTerminal.exe"
$link.WorkingDirectory = $HOME
$link.Save()
$userPath = [Environment]::GetEnvironmentVariable('Path','User')
if (($userPath -split ';') -notcontains $dest) { [Environment]::SetEnvironmentVariable('Path', "$userPath;$dest", 'User') }
Get-Process WindowsTerminal -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,Path

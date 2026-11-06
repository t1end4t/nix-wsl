. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Common.ps1')
$ErrorActionPreference = 'Continue'
'Operating system:'
Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber | Format-List
'Processes:'
Get-Process | Select-Object ProcessName,Id,SessionId | Format-Table -AutoSize
'Capture packages:'
try { Import-Module Appx -UseWindowsPowerShell -ErrorAction Stop; Get-AppxPackage | Where-Object Name -Match 'ScreenSketch|ChatGPT|Client.CBS' | Select-Object Name,Version,Status,InstallLocation | Format-List } catch { $_.Exception.Message }
'App folders:'
foreach ($folder in @("$env:LOCALAPPDATA\Packages", "$env:APPDATA", "$env:LOCALAPPDATA\OpenAI", "$env:LOCALAPPDATA\ChatGPT")) {
 'Folder: ' + $folder
 Get-ChildItem -LiteralPath $folder -ErrorAction SilentlyContinue | Where-Object Name -Match 'ChatGPT|OpenAI|ScreenSketch' | Select-Object Name,FullName
}
'Clipboard services:'
Get-Service | Where-Object Name -Match 'cbdhsvc|CaptureService' | Format-Table Name,Status,StartType

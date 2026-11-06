. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Common.ps1')
$ErrorActionPreference = 'Continue'
Get-Date
Get-Process | Where-Object ProcessName -Match 'ChatGPT|Snipping|ScreenClipping|UniKey' | Select-Object ProcessName,Id,SessionId,Path | Format-List
try {
 Add-Type -AssemblyName System.Windows.Forms
 $clipData = [Windows.Forms.Clipboard]::GetDataObject()
 if ($null -eq $clipData) { 'ClipboardEmpty' } else { 'Clipboard formats:'; $clipData.GetFormats() }
 if ([Windows.Forms.Clipboard]::ContainsImage()) {
  $clipImage = [Windows.Forms.Clipboard]::GetImage()
  'Image size: {0}x{1}' -f $clipImage.Width,$clipImage.Height
  $clipImage.Dispose()
 }
} catch { $_.Exception.Message }
Get-ChildItem "$env:LOCALAPPDATA\Packages" -Directory -Filter '*ChatGPT*' | Select-Object FullName
Get-ChildItem "$env:APPDATA" -Directory -Filter '*ChatGPT*' | Select-Object FullName
Get-Service cbdhsvc* | Select-Object Name,Status,StartType

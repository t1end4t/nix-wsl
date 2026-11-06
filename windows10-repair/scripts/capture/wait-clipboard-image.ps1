. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Common.ps1')
Add-Type -AssemblyName System.Windows.Forms
$deadline = (Get-Date).AddSeconds(40)
do {
 try {
  if ([Windows.Forms.Clipboard]::ContainsImage()) {
   $clipData = [Windows.Forms.Clipboard]::GetDataObject()
   'IMAGE_FOUND'
   $clipData.GetFormats()
   $clipImage = [Windows.Forms.Clipboard]::GetImage()
   'Dimensions: {0}x{1}' -f $clipImage.Width,$clipImage.Height
   $clipImage.Dispose()
   exit 0
  }
 } catch { $_.Exception.Message }
 Start-Sleep -Milliseconds 500
} while ((Get-Date) -lt $deadline)
'NO_IMAGE_OBSERVED; current formats:'
$clipData = [Windows.Forms.Clipboard]::GetDataObject()
if ($null -ne $clipData) { $clipData.GetFormats() }

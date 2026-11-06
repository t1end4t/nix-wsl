. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Common.ps1')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$testBitmap = [System.Drawing.Bitmap]::new(160,80)
$graphics = [System.Drawing.Graphics]::FromImage($testBitmap)
try {
 $graphics.Clear([System.Drawing.Color]::RoyalBlue)
 $graphics.DrawString('Clipboard test', [System.Drawing.SystemFonts]::DefaultFont, [System.Drawing.Brushes]::White, 20,30)
 [System.Windows.Forms.Clipboard]::SetDataObject($testBitmap,$true,10,100)
 'Test image written. Clipboard formats:'
 [System.Windows.Forms.Clipboard]::GetDataObject().GetFormats()
 'ContainsImage: ' + [System.Windows.Forms.Clipboard]::ContainsImage()
} finally { $graphics.Dispose(); $testBitmap.Dispose() }

. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Common.ps1')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class CaptureInput {
 [DllImport("user32.dll")] public static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern void mouse_event(uint flags,uint dx,uint dy,uint data,UIntPtr extra);
 [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
 public struct POINT { public int X; public int Y; }
}
'@
'Before:'
[Windows.Forms.Clipboard]::GetDataObject().GetFormats()
$oldPosition = New-Object CaptureInput+POINT
[void][CaptureInput]::GetCursorPos([ref]$oldPosition)
try {
 [CaptureInput]::keybd_event(0x5B,0,0,[UIntPtr]::Zero)
 [CaptureInput]::keybd_event(0x10,0,0,[UIntPtr]::Zero)
 Start-Sleep -Milliseconds 100
 [CaptureInput]::keybd_event(0x53,0,0,[UIntPtr]::Zero)
 Start-Sleep -Milliseconds 100
 [CaptureInput]::keybd_event(0x53,0,2,[UIntPtr]::Zero)
 [CaptureInput]::keybd_event(0x10,0,2,[UIntPtr]::Zero)
 [CaptureInput]::keybd_event(0x5B,0,2,[UIntPtr]::Zero)
 Start-Sleep -Seconds 2
 [void][CaptureInput]::SetCursorPos(30,30)
 [CaptureInput]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
 Start-Sleep -Milliseconds 150
 [void][CaptureInput]::SetCursorPos(110,90)
 Start-Sleep -Milliseconds 150
 [CaptureInput]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
 Start-Sleep -Seconds 2
 'After:'
 [Windows.Forms.Clipboard]::GetDataObject().GetFormats()
 if ([Windows.Forms.Clipboard]::ContainsImage()) {
  $img = [Windows.Forms.Clipboard]::GetImage()
  'Image dimensions: {0}x{1}' -f $img.Width,$img.Height
  $img.Dispose()
 }
} finally { [void][CaptureInput]::SetCursorPos($oldPosition.X,$oldPosition.Y) }

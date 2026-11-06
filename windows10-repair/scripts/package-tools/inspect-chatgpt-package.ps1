. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Common.ps1')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead("$RepairPayload\ChatGPT-x64.msix")
try {
 $entry = $zip.GetEntry('AppxManifest.xml')
 $reader = [IO.StreamReader]::new($entry.Open())
 $xmlText = $reader.ReadToEnd()
 $reader.Dispose()
 $xmlText | Set-Content "$RepairPayload\ChatGPT-AppxManifest.xml"
 [xml]$manifest = $xmlText
 $manifest.Package.Identity | Format-List
 $manifest.Package.Dependencies.ChildNodes | Format-List
} finally { $zip.Dispose() }

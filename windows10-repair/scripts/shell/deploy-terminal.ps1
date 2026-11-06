. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Common.ps1')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$pkg = "$RepairPayload\Terminal-Package"
$bundle = (Get-ChildItem "$pkg\*.msixbundle").FullName
$zip = [IO.Compression.ZipFile]::OpenRead($bundle)
$zip.Entries | Select-Object FullName
$entry = $zip.Entries | Where-Object { $_.Name -match '_x64\.msix$' } | Select-Object -First 1
if (!$entry) { throw 'x64 package missing' }
$msix = "$pkg\terminal-x64.msix"
[IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$msix,$true)
$zip.Dispose()
$dest = "$RepairPayload\WindowsTerminal"
[IO.Compression.ZipFile]::ExtractToDirectory($msix,$dest,$true)
$dep = (Get-ChildItem "$pkg\*x64*.appx").FullName
[IO.Compression.ZipFile]::ExtractToDirectory($dep,"$pkg\VCLibs",$true)
Get-ChildItem "$pkg\VCLibs" -Filter *.dll | Copy-Item -Destination $dest
Get-Content "$dest\AppxManifest.xml" | Select-String 'MinVersion|PackageDependency'
Get-Item "$dest\WindowsTerminal.exe"

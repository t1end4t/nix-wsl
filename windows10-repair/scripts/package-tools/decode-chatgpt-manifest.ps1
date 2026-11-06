. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Common.ps1')
$b = [IO.File]::ReadAllBytes("$RepairPayload\ChatGPT-manifest-entry.bin")
$start = 30 + [BitConverter]::ToUInt16($b,26) + [BitConverter]::ToUInt16($b,28)
$ms = [IO.MemoryStream]::new($b,$start,2106)
$ds = [IO.Compression.DeflateStream]::new($ms,[IO.Compression.CompressionMode]::Decompress)
$reader = [IO.StreamReader]::new($ds)
$xml = $reader.ReadToEnd()
$reader.Dispose()
$xml | Set-Content "$RepairPayload\ChatGPT-AppxManifest.xml"
[xml]$manifest = $xml
$manifest.Package.Dependencies.ChildNodes | Format-List

. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Common.ps1')
$b = [IO.File]::ReadAllBytes("$RepairPayload\ChatGPT-zip-tail.bin")
for ($i=0; $i -lt $b.Length-46; $i++) {
 if ([BitConverter]::ToUInt32($b,$i) -eq 0x02014b50) {
  $n = [BitConverter]::ToUInt16($b,$i+28)
  if ($i+46+$n -gt $b.Length) { continue }
  $name = [Text.Encoding]::UTF8.GetString($b,$i+46,$n)
  if ($name -eq 'AppxManifest.xml') {
   $offset = [BitConverter]::ToUInt32($b,$i+42)
   $size = [BitConverter]::ToUInt32($b,$i+20)
   "Manifest offset=$offset compressedSize=$size range=$offset-$($offset+$size+1024)"
  }
 }
}

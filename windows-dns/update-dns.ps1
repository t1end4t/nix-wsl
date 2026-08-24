#Requires -RunAsAdministrator

$src = "$PSScriptRoot"
$dst = "C:\Program Files\dnscrypt-proxy"

& "$src\build-blocklist.ps1"

Copy-Item "$src\blocked-names.generated.txt" "$dst\blocked-names.generated.txt"
Copy-Item "$src\allowed-names.txt" "$dst\allowed-names.txt"
Copy-Item "$src\cloaking-rules.txt" "$dst\cloaking-rules.txt"
Copy-Item "$src\dnscrypt-proxy.toml" "$dst\dnscrypt-proxy.toml"

Restart-Service dnscrypt-proxy
ipconfig /flushdns | Out-Null
Write-Host "DNS config updated, service restarted, cache flushed."

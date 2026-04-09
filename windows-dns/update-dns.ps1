#Requires -RunAsAdministrator

$src = "$PSScriptRoot"
$dst = "C:\Program Files\dnscrypt-proxy"

Copy-Item "$src\blocked-names.txt" "$dst\blocked-names.txt"
Copy-Item "$src\allowed-names.txt" "$dst\allowed-names.txt"
Copy-Item "$src\cloaking-rules.txt" "$dst\cloaking-rules.txt"
Copy-Item "$src\dnscrypt-proxy.toml" "$dst\dnscrypt-proxy.toml"

Restart-Service dnscrypt-proxy
Write-Host "DNS config updated and service restarted."

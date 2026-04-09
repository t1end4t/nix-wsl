#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs dnscrypt-proxy as a Windows service, mirroring the NixOS workstation DNS setup.

.DESCRIPTION
    - Downloads the latest dnscrypt-proxy Windows x64 release
    - Installs it to $INSTALL_DIR
    - Copies config files from this script's directory
    - Registers and starts the Windows service
    - Points all active network adapters to 127.0.0.1 / ::1

.NOTES
    Run from an elevated PowerShell prompt.
    After this, run update-hosts.ps1 to apply Steven Black's blocklist.
#>

$INSTALL_DIR = "C:\Program Files\dnscrypt-proxy"
$SCRIPT_DIR  = Split-Path -Parent $MyInvocation.MyCommand.Path

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- 1. Download latest release ---
Write-Host ""
Write-Host "[1/5] Fetching latest dnscrypt-proxy release from GitHub..."
$release = Invoke-RestMethod "https://api.github.com/repos/DNSCrypt/dnscrypt-proxy/releases/latest"
$asset   = $release.assets | Where-Object { $_.name -match "win64.*\.zip$" } | Select-Object -First 1

if (-not $asset) {
    throw "Could not find a windows_x64 zip asset in the latest release."
}

$zipPath = "$env:TEMP\dnscrypt-proxy.zip"
Write-Host "  Downloading $($asset.name)..."
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath

# --- 2. Extract ---
Write-Host ""
Write-Host "[2/5] Extracting..."
$extractDir = "$env:TEMP\dnscrypt-proxy-extract"
if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
Expand-Archive -Path $zipPath -DestinationPath $extractDir

# The zip may contain a single subdirectory -- find the actual content root
$contentRoot = Get-ChildItem $extractDir -Directory | Select-Object -First 1
if ($contentRoot) {
    $contentRoot = $contentRoot.FullName
} else {
    $contentRoot = $extractDir
}

# --- 3. Install binary ---
Write-Host ""
Write-Host "[3/5] Installing to $INSTALL_DIR..."
New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
Copy-Item -Path "$contentRoot\*" -Destination $INSTALL_DIR -Recurse -Force

# --- 4. Copy our config files ---
Write-Host "  Copying config files..."
$configFiles = @('dnscrypt-proxy.toml', 'blocked-names.txt', 'allowed-names.txt', 'cloaking-rules.txt')
foreach ($file in $configFiles) {
    $src = Join-Path $SCRIPT_DIR $file
    if (Test-Path $src) {
        Copy-Item $src $INSTALL_DIR -Force
    } else {
        Write-Warning "Missing $file in $SCRIPT_DIR -- skipping."
    }
}

# --- 5. Register & start the service ---
Write-Host ""
Write-Host "[4/5] Installing Windows service..."
Push-Location $INSTALL_DIR
try {
    & ".\dnscrypt-proxy.exe" -service install
    & ".\dnscrypt-proxy.exe" -service start
} finally {
    Pop-Location
}

# --- 6. Point DNS to localhost ---
Write-Host ""
Write-Host "[5/5] Setting DNS servers to 127.0.0.1 / ::1 on active adapters..."
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
foreach ($adapter in $adapters) {
    Write-Host "  $($adapter.Name)"
    Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses '127.0.0.1', '::1'
}

Write-Host ""
Write-Host "Done! dnscrypt-proxy is running as a Windows service."
Write-Host "  Config : $INSTALL_DIR\dnscrypt-proxy.toml"
Write-Host ""
Write-Host "  Next step: run update-hosts.ps1 (as admin) to apply Steven Black's blocklist."
Write-Host ""
Write-Host "  To uninstall later:"
Write-Host ("    cd '" + $INSTALL_DIR + "'")
Write-Host "    .\dnscrypt-proxy.exe -service stop"
Write-Host "    .\dnscrypt-proxy.exe -service uninstall"

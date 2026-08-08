#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Uninstalls dnscrypt-proxy and resets Windows DNS settings.

.DESCRIPTION
    - Resets DNS server addresses on active adapters back to automatic/DHCP
    - Verifies DNS works before stopping and uninstalling dnscrypt-proxy

.NOTES
    Run from an elevated PowerShell prompt.
    This script does not delete the installation directory.
#>

$INSTALL_DIR = "C:\Program Files\dnscrypt-proxy"
$EXE_PATH    = Join-Path $INSTALL_DIR "dnscrypt-proxy.exe"

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "[1/2] Resetting DNS servers to automatic on active adapters..."

$adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
$dnsBackup = @{}

foreach ($adapter in $adapters) {
    $dnsBackup[$adapter.ifIndex] = @(
        Get-DnsClientServerAddress `
            -InterfaceIndex $adapter.ifIndex `
            -ErrorAction Stop |
            Select-Object -ExpandProperty ServerAddresses
    )

    Write-Host "  $($adapter.Name)"
    Set-DnsClientServerAddress `
        -InterfaceIndex $adapter.ifIndex `
        -ResetServerAddresses `
        -ErrorAction Stop
}

ipconfig /flushdns | Out-Null

$dnsWorks = $false

for ($attempt = 1; $attempt -le 5; $attempt++) {
    try {
        Resolve-DnsName `
            -Name "example.com" `
            -Type A `
            -DnsOnly `
            -ErrorAction Stop |
            Out-Null

        $dnsWorks = $true
        break
    }
    catch {
        Start-Sleep -Seconds 2
    }
}

if (-not $dnsWorks) {
    foreach ($adapter in $adapters) {
        $serverAddresses = $dnsBackup[$adapter.ifIndex]

        if ($serverAddresses.Count -gt 0) {
            Set-DnsClientServerAddress `
                -InterfaceIndex $adapter.ifIndex `
                -ServerAddresses $serverAddresses `
                -ErrorAction Continue
        }
    }

    ipconfig /flushdns | Out-Null
    throw "Automatic DNS did not become usable. Previous DNS settings were restored; dnscrypt-proxy was left running."
}

Write-Host ""
Write-Host "[2/2] Uninstalling dnscrypt-proxy service..."

if (Test-Path $EXE_PATH) {
    Push-Location $INSTALL_DIR
    try {
        try {
            & ".\dnscrypt-proxy.exe" -service stop
        } catch {
            Write-Warning "Could not stop dnscrypt-proxy service. It may already be stopped."
        }

        try {
            & ".\dnscrypt-proxy.exe" -service uninstall
        } catch {
            Write-Warning "Could not uninstall dnscrypt-proxy service. It may already be removed."
        }
    } finally {
        Pop-Location
    }
} else {
    Write-Warning "dnscrypt-proxy.exe not found at $EXE_PATH -- skipping service uninstall."
}

Write-Host ""
Write-Host "Done! dnscrypt-proxy service removed and adapter DNS reset."
Write-Host "  Install folder left in place: $INSTALL_DIR"

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

# Use inbox tools when stripped Windows installations lack networking modules.
$useNativeDns = -not (
    (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue) -and
    (Get-Command Get-DnsClientServerAddress -ErrorAction SilentlyContinue) -and
    (Get-Command Set-DnsClientServerAddress -ErrorAction SilentlyContinue) -and
    (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue)
)

function Set-NativeDns {
    param($Adapter, $Configuration)

    foreach ($family in @('ipv4', 'ipv6')) {
        $servers = @($Configuration[$family])
        $arguments = @('interface', $family, 'set', 'dnsservers', "name=$($Adapter.ifIndex)")
        if ($servers.Count -eq 0) {
            $arguments += 'source=dhcp'
        } else {
            $arguments += @('source=static', "address=$($servers[0])", 'validate=no')
        }
        & netsh.exe @arguments | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Could not set $family DNS on $($Adapter.Name)." }
        for ($i = 1; $i -lt $servers.Count; $i++) {
            & netsh.exe interface $family add dnsservers "name=$($Adapter.ifIndex)" "address=$($servers[$i])" "index=$($i + 1)" validate=no | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Could not restore $family DNS on $($Adapter.Name)." }
        }
    }
}

Write-Host ""
Write-Host "[1/2] Resetting DNS servers to automatic on active adapters..."

$adapters = if ($useNativeDns) {
    Get-Command Get-CimInstance, netsh.exe, ipconfig.exe -ErrorAction Stop | Out-Null
    Get-CimInstance Win32_NetworkAdapter -Filter 'NetConnectionStatus = 2' |
        Select-Object @{n='ifIndex';e={$_.InterfaceIndex}}, @{n='Name';e={$_.NetConnectionID}}, GUID
} else {
    Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
}
$adapters = @($adapters)
if ($adapters.Count -eq 0) { throw 'No active network adapters were found; service left unchanged.' }
$dnsBackup = @{}

foreach ($adapter in $adapters) {
    if ($useNativeDns) {
        $configuration = @{}
        foreach ($family in @('ipv4', 'ipv6')) {
            $service = if ($family -eq 'ipv4') { 'Tcpip' } else { 'Tcpip6' }
            $path = "HKLM:\SYSTEM\CurrentControlSet\Services\$service\Parameters\Interfaces\$($adapter.GUID)"
            $entry = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
            $property = $entry.PSObject.Properties['NameServer']
            $configuration[$family] = @(
                if ($property -and $property.Value) {
                    ([string]$property.Value) -split '[,;\s]+' | Where-Object { $_ }
                }
            )
        }
        $dnsBackup[$adapter.ifIndex] = $configuration
        continue
    }
    $dnsBackup[$adapter.ifIndex] = @(
        Get-DnsClientServerAddress `
            -InterfaceIndex $adapter.ifIndex `
            -ErrorAction Stop |
            Select-Object -ExpandProperty ServerAddresses
    )

}

try {
foreach ($adapter in $adapters) {
    Write-Host "  $($adapter.Name)"
    if ($useNativeDns) {
        Set-NativeDns $adapter @{ipv4=@(); ipv6=@()}
        continue
    }
    Set-DnsClientServerAddress `
        -InterfaceIndex $adapter.ifIndex `
        -ResetServerAddresses `
        -ErrorAction Stop
}

ipconfig /flushdns | Out-Null

$dnsWorks = $false

for ($attempt = 1; $attempt -le 5; $attempt++) {
    try {
        if ($useNativeDns) {
            $addresses = [System.Net.Dns]::GetHostAddresses('example.com')
            if ($addresses.Count -eq 0) { throw 'DNS returned no addresses.' }
        } else {
        Resolve-DnsName `
            -Name "example.com" `
            -Type A `
            -DnsOnly `
            -ErrorAction Stop |
            Out-Null
        }

        $dnsWorks = $true
        break
    }
    catch {
        Start-Sleep -Seconds 2
    }
}

if (-not $dnsWorks) {
    throw 'Automatic DNS did not become usable.'
}
}
catch {
    $failure = $_
    $restoreFailed = $false
    foreach ($adapter in $adapters) {
        if ($useNativeDns) {
            try { Set-NativeDns $adapter $dnsBackup[$adapter.ifIndex] }
            catch { $restoreFailed = $true; Write-Warning $_ }
            continue
        }
        $serverAddresses = $dnsBackup[$adapter.ifIndex]

        if ($serverAddresses.Count -gt 0) {
            Set-DnsClientServerAddress `
                -InterfaceIndex $adapter.ifIndex `
                -ServerAddresses $serverAddresses `
                -ErrorAction Continue
        }
    }

    ipconfig /flushdns | Out-Null
    if ($restoreFailed) {
        throw "DNS reset failed: $failure Rollback was incomplete; dnscrypt-proxy was left running."
    }
    throw "DNS reset failed: $failure Previous DNS settings were restored; dnscrypt-proxy was left running."
}

Write-Host ""
Write-Host "[2/2] Uninstalling dnscrypt-proxy service..."

if (Test-Path $EXE_PATH) {
    Push-Location $INSTALL_DIR
    try {
        try {
            & ".\dnscrypt-proxy.exe" -service stop
            if ($LASTEXITCODE -ne 0) { throw "Service stop exited with code $LASTEXITCODE." }
        } catch {
            Write-Warning "Could not stop dnscrypt-proxy service. It may already be stopped."
        }

        try {
            & ".\dnscrypt-proxy.exe" -service uninstall
            if ($LASTEXITCODE -ne 0) { throw "Service uninstall exited with code $LASTEXITCODE." }
        } catch {
            throw "Could not uninstall dnscrypt-proxy service: $_"
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

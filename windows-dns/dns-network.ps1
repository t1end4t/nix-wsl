# Networking helpers for setup-dns.ps1. Dot-sourcing this file changes no settings.
# The native path needs neither Windows PowerShell nor DnsClient/NetAdapter.

function Initialize-DnsNetworking {
    $requiredCommands = @(
        'Resolve-DnsName', 'Get-NetAdapter',
        'Get-DnsClientServerAddress', 'Set-DnsClientServerAddress'
    )
    $missingCommands = @(
        foreach ($command in $requiredCommands) {
            if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { $command }
        }
    )
    $script:DnsUseNativeTools = $missingCommands.Count -gt 0
    if ($script:DnsUseNativeTools) {
        Get-Command Get-CimInstance, netsh.exe, ipconfig.exe -ErrorAction Stop | Out-Null
        Write-Warning "Windows networking cmdlets unavailable ($($missingCommands -join ', ')). Using CIM, .NET and netsh.exe."
    }
}

function Get-DnsSetupAdapters {
    if ($script:DnsUseNativeTools) {
        Get-CimInstance Win32_NetworkAdapter `
            -Filter 'NetConnectionStatus = 2 AND PhysicalAdapter = TRUE' -ErrorAction Stop |
            Select-Object @{n='ifIndex';e={$_.InterfaceIndex}},
                @{n='Name';e={$_.NetConnectionID}}, GUID
    }
    else {
        Get-NetAdapter -ErrorAction Stop |
            Where-Object { $_.Status -eq 'Up' -and $_.HardwareInterface } |
            Select-Object ifIndex, Name, @{n='GUID';e={$_.InterfaceGuid}}
    }
}

function Get-DnsSetupConfiguration {
    param([Parameter(Mandatory)]$Adapter)

    # GetAdaptersAddresses (through .NET) includes effective DHCP/RA DNS servers.
    # Registry reads distinguish automatic DNS from a static override for rollback.
    $nic = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
        Where-Object { $_.Id.Trim('{}') -eq ([string]$Adapter.GUID).Trim('{}') } |
        Select-Object -First 1
    if (-not $nic) { throw "Could not inspect DNS for $($Adapter.Name)." }
    $effective = @($nic.GetIPProperties().DnsAddresses)
    foreach ($family in @('ipv4', 'ipv6')) {
        $component = if ($family -eq 'ipv4') {
            [System.Net.NetworkInformation.NetworkInterfaceComponent]::IPv4
        } else { [System.Net.NetworkInformation.NetworkInterfaceComponent]::IPv6 }
        if (-not $nic.Supports($component)) { continue }
        $service = if ($family -eq 'ipv4') { 'Tcpip' } else { 'Tcpip6' }
        $addressFamily = if ($family -eq 'ipv4') {
            [System.Net.Sockets.AddressFamily]::InterNetwork
        } else { [System.Net.Sockets.AddressFamily]::InterNetworkV6 }
        $guid = '{' + ([string]$Adapter.GUID).Trim('{}') + '}'
        $path = "HKLM:\SYSTEM\CurrentControlSet\Services\$service\Parameters\Interfaces\$guid"
        $entry = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
        $property = $entry.PSObject.Properties['NameServer']
        $static = @(
            if ($property -and $property.Value) {
                (@($property.Value) -join ',') -split '[,;\s]+' | Where-Object { $_ }
            }
        )
        # Refuse a malformed snapshot before any network writes.
        foreach ($address in $static) {
            if ([System.Net.IPAddress]::Parse($address).AddressFamily -ne $addressFamily) {
                throw "Unexpected $family DNS address on $($Adapter.Name): $address"
            }
        }
        [pscustomobject]@{
            InterfaceIndex = $Adapter.ifIndex
            Family = $family
            StaticServerAddresses = $static
            ServerAddresses = @(@(
                $static
                $effective | Where-Object AddressFamily -eq $addressFamily |
                    ForEach-Object { $_.ToString() }
            ) | Select-Object -Unique)
        }
    }
}

function Set-DnsSetupAddresses {
    param(
        [Parameter(Mandatory)][int]$InterfaceIndex,
        [Parameter(Mandatory)][ValidateSet('ipv4', 'ipv6')][string]$Family,
        [string[]]$ServerAddresses = @()
    )
    if (-not $script:DnsUseNativeTools) {
        $entry = Get-DnsClientServerAddress -InterfaceIndex $InterfaceIndex `
            -AddressFamily $Family -ErrorAction Stop
        if ($ServerAddresses.Count -eq 0) {
            $entry | Set-DnsClientServerAddress -ResetServerAddresses -ErrorAction Stop
        } else {
            $entry | Set-DnsClientServerAddress -ServerAddresses $ServerAddresses -ErrorAction Stop
        }
        return
    }
    $arguments = @('interface', $Family, 'set', 'dnsservers', "name=$InterfaceIndex")
    if ($ServerAddresses.Count -eq 0) {
        $arguments += 'source=dhcp'
    } else {
        $arguments += @('source=static', "address=$($ServerAddresses[0])", 'validate=no')
    }
    $output = & netsh.exe @arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "netsh could not set $Family DNS on interface ${InterfaceIndex}: $output"
    }
    for ($i = 1; $i -lt $ServerAddresses.Count; $i++) {
        $output = & netsh.exe interface $Family add dnsservers "name=$InterfaceIndex" `
            "address=$($ServerAddresses[$i])" "index=$($i + 1)" validate=no 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "netsh could not add $Family DNS on interface ${InterfaceIndex}: $output"
        }
    }
}

function Test-DnsSetupQuery {
    param(
        [string]$Server,
        [ValidateRange(1,65535)][int]$Port = 53,
        [ValidateRange(1,60000)][int]$TimeoutMilliseconds = 2000
    )
    if (-not $script:DnsUseNativeTools) {
        $arguments = @{ Name = 'example.com'; Type = 'A'; DnsOnly = $true; ErrorAction = 'Stop' }
        if ($Server) { $arguments.Server = $Server }
        return [bool](Resolve-DnsName @arguments)
    }
    if (-not $Server) {
        # Exercise the Windows resolver after cutover, including its adapter order.
        return @([System.Net.Dns]::GetHostAddresses('example.com')).Count -gt 0
    }

    # Probe the exact loopback listener, bypassing the OS cache and other adapters.
    # A fixed example.com IN A question avoids parsing localized nslookup output.
    $address = [System.Net.IPAddress]::Parse($Server)
    if (-not [System.Net.IPAddress]::IsLoopback($address)) {
        throw 'Direct DNS probes must target a loopback address.'
    }
    $id = Get-Random -Minimum 0 -Maximum 65536
    [byte[]]$query = @(
        ($id -shr 8), ($id -band 255), 1, 0, 0, 1, 0, 0, 0, 0, 0, 0,
        7, 101, 120, 97, 109, 112, 108, 101, 3, 99, 111, 109, 0, 0, 1, 0, 1
    )
    $client = [System.Net.Sockets.UdpClient]::new($address.AddressFamily)
    try {
        $client.Client.ReceiveTimeout = $TimeoutMilliseconds
        $client.Connect($address, $Port)
        [void]$client.Send($query, $query.Length)
        $remote = [System.Net.IPEndPoint]::new($address, $Port)
        $response = $client.Receive([ref]$remote)
        # Check identity, response/opcode/truncation/rcode, echoed question and answers.
        if ($response.Length -lt ($query.Length + 16) -or
            $response[0] -ne $query[0] -or $response[1] -ne $query[1] -or
            ($response[2] -band 0xFA) -ne 0x80 -or ($response[3] -band 0x0F) -ne 0 -or
            $response[4] -ne 0 -or $response[5] -ne 1 -or
            ($response[6] -eq 0 -and $response[7] -eq 0)) { return $false }
        for ($i = 12; $i -lt $query.Length; $i++) {
            if ($response[$i] -ne $query[$i]) { return $false }
        }
        # Require an actual IN A answer, rather than only a positive header.
        $position = $query.Length
        $answerCount = ([int]$response[6] -shl 8) + $response[7]
        for ($record = 0; $record -lt $answerCount; $record++) {
            while ($true) {
                if ($position -ge $response.Length) { return $false }
                $label = [int]$response[$position++]
                if ($label -eq 0) { break }
                if (($label -band 0xC0) -eq 0xC0) {
                    if ($position -ge $response.Length) { return $false }
                    $pointer = (($label -band 0x3F) -shl 8) + $response[$position++]
                    if ($pointer -ge $response.Length) { return $false }
                    break
                }
                if ($label -gt 63) { return $false }
                $position += $label
            }
            if (($position + 10) -gt $response.Length) { return $false }
            $type = ([int]$response[$position] -shl 8) + $response[$position + 1]
            $class = ([int]$response[$position + 2] -shl 8) + $response[$position + 3]
            $length = ([int]$response[$position + 8] -shl 8) + $response[$position + 9]
            $position += 10
            if (($position + $length) -gt $response.Length) { return $false }
            if ($type -eq 1 -and $class -eq 1 -and $length -eq 4) { return $true }
            $position += $length
        }
        return $false
    }
    finally { $client.Dispose() }
}

# Run with pwsh -NoProfile -File ./tests/dns-network.Tests.ps1 (no Pester required).
# Uses loopback UDP fixtures; all adapter writes and DNS cache flushes are mocked.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'dns-network.ps1')

function Assert-True($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Net.Sockets;
using System.Threading;
public sealed class SetupDnsFixture : IDisposable {
    readonly UdpClient socket;
    readonly Thread worker;
    public int Port { get; private set; }
    public SetupDnsFixture(string address, string mode) {
        var ip = IPAddress.Parse(address);
        socket = new UdpClient(new IPEndPoint(ip, 0));
        socket.Client.ReceiveTimeout = 5000;
        Port = ((IPEndPoint)socket.Client.LocalEndPoint).Port;
        worker = new Thread(() => {
            try {
                var remote = new IPEndPoint(ip, 0);
                byte[] query = socket.Receive(ref remote);
                byte[] reply = new byte[query.Length + 16];
                Array.Copy(query, reply, query.Length);
                reply[2] = 0x81; reply[3] = 0x80; reply[7] = 1;
                byte[] answer = { 0xc0, 12, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 203, 0, 113, 1 };
                Array.Copy(answer, 0, reply, query.Length, answer.Length);
                if (mode == "empty") reply[7] = 0;
                if (mode == "nxdomain") reply[3] = 0x83;
                if (mode == "truncated") reply[2] |= 2;
                if (mode == "wrong-id") reply[0] ^= 1;
                if (mode == "wrong-question") reply[13] ^= 1;
                if (mode == "not-a") reply[query.Length + 3] = 28;
                if (mode == "bad-length") reply[query.Length + 11] = 99;
                if (mode == "short") Array.Resize(ref reply, 12);
                socket.Send(reply, reply.Length, remote);
            } catch (SocketException) {} catch (ObjectDisposedException) {}
        });
        worker.IsBackground = true;
        worker.Start();
    }
    public void Dispose() { socket.Dispose(); worker.Join(6000); }
}
'@

$script:DnsUseNativeTools = $true
foreach ($server in @('127.0.0.1', '::1')) {
    foreach ($mode in @('answer','empty','nxdomain','truncated','wrong-id','wrong-question','not-a','bad-length','short')) {
        $fixture = [SetupDnsFixture]::new($server, $mode)
        try {
            $result = Test-DnsSetupQuery -Server $server -Port $fixture.Port
            Assert-True ($result -eq ($mode -eq 'answer')) "Unexpected $mode result for $server"
        } finally { $fixture.Dispose() }
    }
}
$idle = [System.Net.Sockets.UdpClient]::new([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Loopback, 0))
try {
    $timedOut = $false
    try { Test-DnsSetupQuery -Server '127.0.0.1' -Port $idle.Client.LocalEndPoint.Port -TimeoutMilliseconds 50 | Out-Null }
    catch { $timedOut = $true }
    Assert-True $timedOut 'A nonresponsive local resolver must fail.'
} finally { $idle.Dispose() }
Write-Output 'PASS: IPv4/IPv6 DNS replies, negative replies, malformed replies and timeout.'

# Test cmdlet dispatch as well as native dispatch without writing real DNS.
$script:CmdletCalls = [System.Collections.Generic.List[object]]::new()
function Get-DnsClientServerAddress { param($InterfaceIndex,$AddressFamily,$ErrorAction)
    [pscustomobject]@{ InterfaceIndex=$InterfaceIndex; Family=$AddressFamily }
}
function Set-DnsClientServerAddress { param([Parameter(ValueFromPipeline)]$InputObject,$ServerAddresses,[switch]$ResetServerAddresses)
    process { $script:CmdletCalls.Add(@{Family=$InputObject.Family;Reset=[bool]$ResetServerAddresses;Servers=@($ServerAddresses)}) }
}
function Resolve-DnsName { param($Name,$Type,$DnsOnly,$ErrorAction,$Server)
    [pscustomobject]@{ IPAddress='203.0.113.1' }
}
function Get-NetAdapter {}
Initialize-DnsNetworking
Assert-True (-not $script:DnsUseNativeTools) 'Available networking cmdlets should be preferred.'
Set-DnsSetupAddresses -InterfaceIndex 8 -Family ipv4 -ServerAddresses @('127.0.0.1','192.0.2.1')
Set-DnsSetupAddresses -InterfaceIndex 8 -Family ipv6
Assert-True ($script:CmdletCalls[0].Family -eq 'ipv4' -and $script:CmdletCalls[0].Servers.Count -eq 2) 'Cmdlet path lost IPv4 DNS addresses.'
Assert-True ($script:CmdletCalls[1].Family -eq 'ipv6' -and $script:CmdletCalls[1].Reset) 'Cmdlet reset must preserve automatic DNS.'
Assert-True (Test-DnsSetupQuery -Server '127.0.0.1') 'Cmdlet query failed.'
Remove-Item Function:Get-NetAdapter
Initialize-DnsNetworking
Assert-True $script:DnsUseNativeTools 'A missing cmdlet must select the native backend.'
Write-Output 'PASS: backend selection and per-family cmdlet dispatch.'

$script:NativeCalls = [System.Collections.Generic.List[object]]::new()
$script:FailAt = 0
$script:FailRollback = $false
function netsh.exe {
    $script:NativeCalls.Add(@($args))
    $global:LASTEXITCODE = 0
    if ($script:NativeCalls.Count -eq $script:FailAt -or
        ($script:FailRollback -and 'source=dhcp' -in $args)) { $global:LASTEXITCODE = 1 }
}
function ipconfig.exe { $global:LASTEXITCODE = 0 }
function Start-Sleep { param($Seconds) }
function Test-InternetConnectivity { return $script:InternetWorks }
function Test-DnsSetupQuery { return $script:ResolutionWorks }
function Get-DnsSetupAdapters { [pscustomobject]@{ifIndex=8;Name='Fixture';GUID='{fixture}'} }
function Get-DnsSetupConfiguration { param($Adapter)
    if ($script:SnapshotFails) { throw 'Snapshot unavailable.' }
    [pscustomobject]@{InterfaceIndex=8;Family='ipv4';StaticServerAddresses=@();ServerAddresses=@('192.0.2.1')}
    [pscustomobject]@{InterfaceIndex=8;Family='ipv6';StaticServerAddresses=@('2001:db8::1','2001:db8::2');ServerAddresses=@('2001:db8::1','2001:db8::2')}
}

# Execute the installer's real cutover/rollback block, with the write boundaries mocked.
$setupPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'setup-dns.ps1'
$setupText = Get-Content -LiteralPath $setupPath -Raw
$tokens = $null; $parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($setupPath,[ref]$tokens,[ref]$parseErrors)
Assert-True (-not $parseErrors) 'Installer syntax check failed.'
foreach ($name in @('Write-Step','Write-OK','Write-Warn','Invoke-NativeChecked','Restore-DnsConfiguration')) {
    $definition = $ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    . ([scriptblock]::Create($definition.Extent.Text))
}
$start = $setupText.IndexOf('Write-Step "[6/7]')
$end = $setupText.IndexOf('# Cleanup', $start)
$cutover = [scriptblock]::Create($setupText.Substring($start,$end-$start))
foreach ($scenario in @('success','ipv4-only','partial-write','verification-failure','internet-failure','rollback-failure','snapshot-failure')) {
    $script:NativeCalls.Clear()
    $script:ResolutionWorks = $scenario -notin @('verification-failure','rollback-failure')
    $script:InternetWorks = $scenario -ne 'internet-failure'
    $script:FailAt = if ($scenario -eq 'partial-write') { 5 } else { 0 }
    $script:FailRollback = $scenario -eq 'rollback-failure'
    $script:SnapshotFails = $scenario -eq 'snapshot-failure'
    $useIPv6 = $scenario -ne 'ipv4-only'
    $caught = $null
    try { . $cutover } catch { $caught = $_ }
    if ($scenario -in @('success','ipv4-only')) {
        Assert-True (-not $caught) "Cutover should succeed for $scenario : $caught"
        $expected = if ($useIPv6) { 5 } else { 2 }
        Assert-True ($script:NativeCalls.Count -eq $expected) "Unexpected writes for $scenario"
        Assert-True ('address=127.0.0.1' -in $script:NativeCalls[0]) 'IPv4 must use the local resolver first.'
        Assert-True ('address=192.0.2.1' -in $script:NativeCalls[1]) 'IPv4 must retain the previous resolver.'
        if ($useIPv6) {
            Assert-True ('address=::1' -in $script:NativeCalls[2]) 'IPv6 must use its own local resolver first.'
        } else {
            Assert-True (@($script:NativeCalls | Where-Object { 'ipv6' -in $_ }).Count -eq 0) 'Untested IPv6 must remain unchanged.'
        }
    } else {
        Assert-True ([bool]$caught) "Cutover should fail for $scenario"
        if ($scenario -eq 'snapshot-failure') {
            Assert-True ($script:NativeCalls.Count -eq 0) 'A failed snapshot must prevent all DNS writes.'
        } else {
            $restores = @($script:NativeCalls | Where-Object { 'source=dhcp' -in $_ })
            Assert-True ($restores.Count -eq 1) 'Rollback must restore automatic IPv4 DNS.'
            Assert-True ('address=2001:db8::1' -in $script:NativeCalls[$script:NativeCalls.Count-2]) 'Rollback lost static IPv6 DNS.'
            Assert-True ('address=2001:db8::2' -in $script:NativeCalls[$script:NativeCalls.Count-1]) 'Rollback lost the second IPv6 DNS server.'
            if ($scenario -eq 'rollback-failure') {
                Assert-True ($caught.ToString() -match 'rollback was incomplete') 'Incomplete rollback must be reported.'
            }
        }
    }
    Write-Output "PASS: $scenario"
}
Write-Output 'All DNS networking tests passed. No adapter settings were changed.'

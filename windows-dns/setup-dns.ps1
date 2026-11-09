#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs dnscrypt-proxy as a Windows service with a safe,
    transactional DNS cutover.

.DESCRIPTION
    The script deliberately keeps the existing Windows DNS configuration
    intact until dnscrypt-proxy has been:

      1. Downloaded successfully
      2. Extracted successfully
      3. Installed successfully
      4. Configured successfully
      5. Registered as a Windows service
      6. Started successfully
      7. Verified to answer DNS queries locally

    Only after all of the above succeeds are active adapters switched
    to the local dnscrypt-proxy resolver.

    If the final DNS cutover fails, the previous DNS configuration is
    automatically restored.

.NOTES
    Run from an elevated PowerShell prompt.

    The script intentionally does NOT change adapter DNS until the
    very end.

    dnscrypt-proxy should be configured to listen on 127.0.0.1:53.
    IPv6 (::1) is only used if the configuration actually contains
    an IPv6 listener.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

$INSTALL_DIR = "C:\Program Files\dnscrypt-proxy"
$SCRIPT_DIR  = Split-Path -Parent $MyInvocation.MyCommand.Path

$SERVICE_NAME = "dnscrypt-proxy"

$TEMP_ROOT   = Join-Path $env:TEMP "dnscrypt-proxy-install"
$ZIP_PATH    = Join-Path $TEMP_ROOT "dnscrypt-proxy.zip"
$EXTRACT_DIR = Join-Path $TEMP_ROOT "extract"

$CONFIG_FILES = @(
    'dnscrypt-proxy.toml',
    'blocked-names.generated.txt',
    'allowed-names.txt',
    'cloaking-rules.txt'
)

. (Join-Path $SCRIPT_DIR 'dns-network.ps1')
. (Join-Path $SCRIPT_DIR 'dns-download.ps1')

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Step {
    param(
        [string]$Message
    )

    Write-Host ""
    Write-Host $Message -ForegroundColor Cyan
}

function Write-OK {
    param(
        [string]$Message
    )

    Write-Host "  OK: $Message" -ForegroundColor Green
}

function Write-Warn {
    param(
        [string]$Message
    )

    Write-Host "  WARNING: $Message" -ForegroundColor Yellow
}

function Invoke-NativeChecked {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter()]
        [string[]]$Arguments = @()
    )

    & $FilePath @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE`: $FilePath $($Arguments -join ' ')"
    }
}

function Test-DnsServer {
    param(
        [Parameter(Mandatory)]
        [string]$Server,

        [int]$Attempts = 15
    )

    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            $result = Test-DnsSetupQuery -Server $Server

            if ($result) {
                return $true
            }
        }
        catch {
            Write-Verbose "DNS probe $i/$Attempts through ${Server}: $($_.Exception.Message)"
            if ($i -eq $Attempts) {
                Write-Warn "DNS query through $Server failed: $($_.Exception.Message)"
            }
            Start-Sleep -Seconds 1
        }
    }

    return $false
}

function Test-InternetConnectivity {
    try {
        # Use the same DNS, proxy, and HTTPS path that the download needs.
        # Direct TCP probes to a public IP can be blocked even when normal
        # Internet access is working.
        Invoke-WebRequest `
            -Uri "https://github.com" `
            -Method Head `
            -UseBasicParsing `
            -TimeoutSec 15 | Out-Null

        return $true
    }
    catch {
        return $false
    }
}

function Restore-DnsConfiguration {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$DnsBackup
    )

    Write-Host ""
    Write-Host "Restoring previous DNS configuration..." -ForegroundColor Yellow

    $restored = $true
    foreach ($entry in $DnsBackup) {
        try {
            Set-DnsSetupAddresses -InterfaceIndex $entry.InterfaceIndex `
                -Family $entry.Family -ServerAddresses $entry.StaticServerAddresses
            Write-OK "Restored $($entry.Family) DNS on interface $($entry.InterfaceIndex)"
        }
        catch {
            $restored = $false
            Write-Warn "Could not restore $($entry.Family) DNS on interface $($entry.InterfaceIndex): $($_.Exception.Message)"
        }
    }

    try {
        Invoke-NativeChecked -FilePath 'ipconfig.exe' -Arguments @('/flushdns') | Out-Null
    }
    catch {
        Write-Warn "Could not flush the DNS cache after rollback: $($_.Exception.Message)"
    }
    return $restored
}

# ---------------------------------------------------------------------------
# Initial network safety check
# ---------------------------------------------------------------------------

Write-Step "[0/7] Checking current network"

# Check the selected backend before downloads or service changes. Stripped
# Windows can use CIM/.NET/netsh without restoring the missing PowerShell modules.
Initialize-DnsNetworking
$adapters = @(Get-DnsSetupAdapters)
if ($adapters.Count -eq 0) {
    throw 'No active hardware network adapters were found. No settings have been changed.'
}
foreach ($adapter in $adapters) {
    $configuration = @(Get-DnsSetupConfiguration -Adapter $adapter)
    if (-not ($configuration | Where-Object Family -eq 'ipv4')) {
        throw "No IPv4 configuration found on $($adapter.Name). No settings have been changed."
    }
}

if (-not (Test-InternetConnectivity)) {
    throw @"
The existing network connection does not appear to have Internet
connectivity.

No DNS settings have been changed.

Fix the current network connection and run the script again.
"@
}

Write-OK "Existing network connectivity is working."

# ---------------------------------------------------------------------------
# Prepare temporary directories
# ---------------------------------------------------------------------------

Write-Step "[1/7] Preparing temporary workspace"

if (Test-Path $TEMP_ROOT) {
    Remove-Item $TEMP_ROOT -Recurse -Force
}

New-Item -ItemType Directory -Path $TEMP_ROOT -Force | Out-Null
New-Item -ItemType Directory -Path $EXTRACT_DIR -Force | Out-Null

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------

Write-Step "[2/7] Fetching latest dnscrypt-proxy release"

$asset = Get-DnscryptReleaseAsset

Write-Host "  Release: $($asset.TagName)"
Write-Host "  Asset:   $($asset.Name)"

Invoke-WebRequest `
    -Uri $asset.DownloadUrl `
    -OutFile $ZIP_PATH

if (-not (Test-Path $ZIP_PATH)) {
    throw "dnscrypt-proxy download failed."
}

Write-OK "Downloaded successfully."

# ---------------------------------------------------------------------------
# Extract
# ---------------------------------------------------------------------------

Write-Step "[3/7] Extracting dnscrypt-proxy"

Expand-Archive `
    -Path $ZIP_PATH `
    -DestinationPath $EXTRACT_DIR `
    -Force

$contentRoot = Get-ChildItem $EXTRACT_DIR -Directory |
    Select-Object -First 1

if ($contentRoot) {
    $contentRoot = $contentRoot.FullName
}
else {
    $contentRoot = $EXTRACT_DIR
}

$binary = Join-Path $contentRoot "dnscrypt-proxy.exe"

if (-not (Test-Path $binary)) {
    throw "dnscrypt-proxy.exe was not found after extraction."
}

Write-OK "Archive extracted."

# ---------------------------------------------------------------------------
# Install files
# ---------------------------------------------------------------------------

Write-Step "[4/7] Installing files and configuration"

$blocklistBuilder = Join-Path $SCRIPT_DIR 'build-blocklist.ps1'

if (-not (Test-Path $blocklistBuilder)) {
    throw "build-blocklist.ps1 was not found at $blocklistBuilder."
}

& $blocklistBuilder

New-Item `
    -ItemType Directory `
    -Force `
    -Path $INSTALL_DIR |
    Out-Null

Copy-Item `
    -Path "$contentRoot\*" `
    -Destination $INSTALL_DIR `
    -Recurse `
    -Force

foreach ($file in $CONFIG_FILES) {
    $src = Join-Path $SCRIPT_DIR $file

    if (Test-Path $src) {
        Copy-Item `
            -Path $src `
            -Destination $INSTALL_DIR `
            -Force

        Write-OK "Copied $file"
    }
    else {
        Write-Warn "Missing $file -- skipping."
    }
}

$installedBinary = Join-Path $INSTALL_DIR "dnscrypt-proxy.exe"
$configPath      = Join-Path $INSTALL_DIR "dnscrypt-proxy.toml"
$logPath         = Join-Path $INSTALL_DIR "dnscrypt-proxy.log"

if (-not (Test-Path $installedBinary)) {
    throw "Installed dnscrypt-proxy.exe was not found."
}

if (-not (Test-Path $configPath)) {
    throw "dnscrypt-proxy.toml was not found."
}

# ---------------------------------------------------------------------------
# Validate configuration BEFORE changing anything network-related
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "  Validating dnscrypt-proxy configuration..."

Push-Location $INSTALL_DIR

try {
    Invoke-NativeChecked `
        -FilePath ".\dnscrypt-proxy.exe" `
        -Arguments @("-check")

    Write-OK "Configuration is valid."
}
finally {
    Pop-Location
}

# ---------------------------------------------------------------------------
# Determine listeners from configuration
# ---------------------------------------------------------------------------

$configText = Get-Content `
    -Path $configPath `
    -Raw

$useIPv4 = $configText -match '127\.0\.0\.1:53'
$useIPv6 = $configText -match '\[::1\]:53'

if (-not $useIPv4) {
    throw @"
dnscrypt-proxy.toml does not appear to listen on 127.0.0.1:53.

The script will not modify Windows DNS because there is no confirmed
IPv4 local DNS listener.

Add this to dnscrypt-proxy.toml:

    listen_addresses = ['127.0.0.1:53']

Then run the installer again.
"@
}

# ---------------------------------------------------------------------------
# Install/start service
#
# IMPORTANT:
# We still have NOT touched Windows DNS.
# ---------------------------------------------------------------------------

Write-Step "[5/7] Installing and validating the dnscrypt-proxy service"

$existingService = Get-Service `
    -Name $SERVICE_NAME `
    -ErrorAction SilentlyContinue

Push-Location $INSTALL_DIR

try {
    if ($existingService) {
        Write-Host "  Reinstalling existing service registration..."

        if ($existingService.Status -ne 'Stopped') {
            Stop-Service `
                -Name $SERVICE_NAME `
                -Force `
                -ErrorAction Stop

            $existingService.WaitForStatus(
                [System.ServiceProcess.ServiceControllerStatus]::Stopped,
                [TimeSpan]::FromSeconds(15)
            )
        }

        Invoke-NativeChecked `
            -FilePath ".\dnscrypt-proxy.exe" `
            -Arguments @("-service", "uninstall")
    }

    Write-Host "  Installing service..."

    Invoke-NativeChecked `
        -FilePath ".\dnscrypt-proxy.exe" `
        -Arguments @("-service", "install")

    Write-OK "Service installed."

    Write-Host "  Starting service..."

    if (Test-Path $logPath) {
        Remove-Item $logPath -Force
    }

    Invoke-NativeChecked `
        -FilePath ".\dnscrypt-proxy.exe" `
        -Arguments @("-service", "start")

    $service = Get-Service `
        -Name $SERVICE_NAME `
        -ErrorAction Stop

    try {
        $service.WaitForStatus(
            [System.ServiceProcess.ServiceControllerStatus]::Running,
            [TimeSpan]::FromSeconds(15)
        )
    }
    catch {
        $service.Refresh()

        $log = if (Test-Path $logPath) {
            (Get-Content $logPath -Tail 50) -join [Environment]::NewLine
        }
        else {
            "No dnscrypt-proxy log was created."
        }

        throw @"
dnscrypt-proxy exited before reaching the Running state.

Service status: $($service.Status)
Log file: $logPath

$log
"@
    }

    $service.Refresh()

    if ($service.Status -ne 'Running') {
        throw "dnscrypt-proxy service did not reach the Running state."
    }

    Write-OK "Service is running."
}
finally {
    Pop-Location
}

# ---------------------------------------------------------------------------
# Verify local DNS BEFORE changing Windows DNS
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "  Testing local dnscrypt-proxy DNS..."

$ipv4DnsOK = Test-DnsServer -Server "127.0.0.1"

if (-not $ipv4DnsOK) {
    $service = Get-Service `
        -Name $SERVICE_NAME `
        -ErrorAction SilentlyContinue

    $serviceStatus = if ($service) {
        $service.Status
    }
    else {
        'NotFound'
    }

    $log = if (Test-Path $logPath) {
        (Get-Content $logPath -Tail 50) -join [Environment]::NewLine
    }
    else {
        "No dnscrypt-proxy log was created."
    }

    throw @"
dnscrypt-proxy did not answer DNS queries through 127.0.0.1.

Windows DNS has NOT been changed.

Service status: $serviceStatus
Log file: $logPath

$log
"@
}

Write-OK "127.0.0.1:53 successfully answered DNS."

$ipv6DnsOK = $false

if ($useIPv6) {
    $ipv6DnsOK = Test-DnsServer -Server "::1"

    if ($ipv6DnsOK) {
        Write-OK "::1:53 successfully answered DNS."
    }
    else {
        Write-Warn "::1:53 is configured but did not answer."

        # Do NOT switch Windows IPv6 DNS to ::1 if it isn't working.
        $useIPv6 = $false
    }
}

# ---------------------------------------------------------------------------
# FINAL PHASE
#
# Everything above this point should have succeeded.
#
# NOW and ONLY NOW do we modify adapter DNS.
# ---------------------------------------------------------------------------

Write-Step "[6/7] FINAL STEP: preparing DNS cutover"

$adapters = @(Get-DnsSetupAdapters)

if (-not $adapters) {
    throw "No active hardware network adapters were found."
}

# Save the current DNS configuration BEFORE touching anything.
$dnsBackup = @()

foreach ($adapter in $adapters) {
    $configuration = @(Get-DnsSetupConfiguration -Adapter $adapter)
    if (-not ($configuration | Where-Object Family -eq 'ipv4')) {
        throw "No IPv4 configuration found on $($adapter.Name); Windows DNS has not been changed."
    }
    $dnsBackup += $configuration
}

# Record each family BEFORE writing, so even a partially failed netsh update
# is rolled back. Unchanged IPv6 settings are not touched during rollback.
$dnsChanges = [System.Collections.Generic.List[object]]::new()

Write-Host ""
Write-Host "The following adapters will be changed:"
foreach ($adapter in $adapters) {
    Write-Host "  $($adapter.Name) [$($adapter.ifIndex)]"
}

Write-Host ""
Write-Host "Local DNS:"
Write-Host "  IPv4: 127.0.0.1"

if ($useIPv6) {
    Write-Host "  IPv6: ::1"
}
else {
    Write-Host "  IPv6: unchanged"
}

# ---------------------------------------------------------------------------
# DNS cutover with automatic rollback
# ---------------------------------------------------------------------------

try {
    Write-Host ""
    Write-Host "Performing final DNS cutover..." -ForegroundColor Yellow

    foreach ($adapter in $adapters) {
        Write-Host "  Configuring $($adapter.Name)..."

        $backups = @($dnsBackup | Where-Object InterfaceIndex -eq $adapter.ifIndex)
        foreach ($backup in $backups) {
            if ($backup.Family -eq 'ipv6' -and -not $useIPv6) { continue }
            $localAddress = if ($backup.Family -eq 'ipv4') { '127.0.0.1' } else { '::1' }
            # Keep previous resolvers in their original IP family as fallbacks.
            $serverAddresses = @($localAddress) + @(
                $backup.ServerAddresses | Where-Object { $_ -notin @('127.0.0.1', '::1') }
            )
            $dnsChanges.Add($backup)
            Set-DnsSetupAddresses -InterfaceIndex $adapter.ifIndex -Family $backup.Family `
                -ServerAddresses @($serverAddresses | Select-Object -Unique)
        }

        Write-OK "$($adapter.Name)"
    }

    # Flush Windows DNS cache after the change.
    Invoke-NativeChecked -FilePath 'ipconfig.exe' -Arguments @('/flushdns') | Out-Null

    Start-Sleep -Seconds 2

    # -----------------------------------------------------------------------
    # Verify the actual system resolver path.
    # -----------------------------------------------------------------------

    Write-Host ""
    Write-Host "Verifying DNS after cutover..."

    $systemDnsOK = $false

    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            $result = Test-DnsSetupQuery

            if ($result) {
                $systemDnsOK = $true
                break
            }
        }
        catch {
            Start-Sleep -Seconds 2
        }
    }

    if (-not $systemDnsOK) {
        throw "System DNS verification failed after the DNS cutover."
    }

    Write-OK "System DNS is working after the cutover."

    # -----------------------------------------------------------------------
    # Final network check.
    # -----------------------------------------------------------------------

    Write-Host ""
    Write-Host "Verifying Internet connectivity..."

    if (-not (Test-InternetConnectivity)) {
        throw "Internet connectivity failed after the DNS cutover."
    }

    Write-OK "Internet connectivity is working."

    Write-Host ""
    Write-Host "DNS cutover completed successfully." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "DNS cutover FAILED." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    $restored = Restore-DnsConfiguration -DnsBackup @($dnsChanges.ToArray())

    Write-Host ""
    if ($restored) {
        Write-Host "The original DNS configuration has been restored." -ForegroundColor Green
    }
    else {
        throw 'Installation failed and DNS rollback was incomplete. dnscrypt-proxy was left running; review the rollback warnings above.'
    }

    Write-Host ""
    Write-Host "dnscrypt-proxy itself was left installed/running."
    Write-Host "Windows DNS was NOT left pointing at a broken resolver."

    throw "Installation aborted safely because the final DNS verification failed."
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

Write-Step "[7/7] Cleaning up"

try {
    if (Test-Path $TEMP_ROOT) {
        Remove-Item `
            $TEMP_ROOT `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }

    Write-OK "Temporary files removed."
}
catch {
    Write-Warn "Could not completely remove temporary files."
}

# ---------------------------------------------------------------------------
# Final status
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "============================================================" `
    -ForegroundColor Green
Write-Host " dnscrypt-proxy installation completed successfully" `
    -ForegroundColor Green
Write-Host "============================================================" `
    -ForegroundColor Green

Write-Host ""
Write-Host "Service : $SERVICE_NAME"
Write-Host "Install : $INSTALL_DIR"
Write-Host "Config  : $configPath"
Write-Host ""

Write-Host "DNS:"
Write-Host "  IPv4 -> 127.0.0.1, then previous DNS as fallback"

if ($useIPv6) {
    Write-Host "  IPv6 -> ::1, then previous DNS as fallback"
}
else {
    Write-Host "  IPv6 -> unchanged"
}

Write-Host ""
Write-Host "The system DNS was only changed after dnscrypt-proxy"
Write-Host "was installed, started, and successfully tested."
Write-Host ""

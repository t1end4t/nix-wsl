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

        [int]$Attempts = 3
    )

    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            $result = Resolve-DnsName `
                -Name "example.com" `
                -Type A `
                -Server $Server `
                -DnsOnly `
                -ErrorAction Stop

            if ($result) {
                return $true
            }
        }
        catch {
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

function Get-ConfiguredDnsAddresses {
    param(
        [Parameter(Mandatory)]
        [int]$InterfaceIndex
    )

    $entry = Get-DnsClientServerAddress `
        -InterfaceIndex $InterfaceIndex `
        -ErrorAction Stop

    return [PSCustomObject]@{
        InterfaceIndex = $InterfaceIndex
        ServerAddresses = @(
            $entry |
                Select-Object -ExpandProperty ServerAddresses
        )
    }
}

function Restore-DnsConfiguration {
    param(
        [Parameter(Mandatory)]
        [array]$DnsBackup
    )

    Write-Host ""
    Write-Host "Restoring previous DNS configuration..." -ForegroundColor Yellow

    foreach ($entry in $DnsBackup) {
        try {
            if ($entry.ServerAddresses.Count -gt 0) {
                Set-DnsClientServerAddress `
                    -InterfaceIndex $entry.InterfaceIndex `
                    -ServerAddresses $entry.ServerAddresses `
                    -ErrorAction Stop
            }
            else {
                Set-DnsClientServerAddress `
                    -InterfaceIndex $entry.InterfaceIndex `
                    -ResetServerAddresses `
                    -ErrorAction Stop
            }

            Write-OK "Restored interface $($entry.InterfaceIndex)"
        }
        catch {
            Write-Warn "Could not restore interface $($entry.InterfaceIndex): $($_.Exception.Message)"
        }
    }

    ipconfig /flushdns | Out-Null
}

# ---------------------------------------------------------------------------
# Initial network safety check
# ---------------------------------------------------------------------------

Write-Step "[0/7] Checking current network"

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

$release = Invoke-RestMethod `
    "https://api.github.com/repos/DNSCrypt/dnscrypt-proxy/releases/latest"

$asset = $release.assets |
    Where-Object {
        $_.name -match '^dnscrypt-proxy.*win64.*\.zip$'
    } |
    Select-Object -First 1

if (-not $asset) {
    throw "Could not find a Windows x64 dnscrypt-proxy ZIP asset."
}

Write-Host "  Release: $($release.tag_name)"
Write-Host "  Asset:   $($asset.name)"

Invoke-WebRequest `
    -Uri $asset.browser_download_url `
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

$adapters = Get-NetAdapter |
    Where-Object {
        $_.Status -eq 'Up' -and
        $_.HardwareInterface -eq $true
    }

if (-not $adapters) {
    throw "No active hardware network adapters were found."
}

# Save the current DNS configuration BEFORE touching anything.
$dnsBackup = @()

foreach ($adapter in $adapters) {
    $dnsBackup += Get-ConfiguredDnsAddresses `
        -InterfaceIndex $adapter.ifIndex
}

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

        $backup = $dnsBackup |
            Where-Object { $_.InterfaceIndex -eq $adapter.ifIndex } |
            Select-Object -First 1

        $serverAddresses = @('127.0.0.1')

        if ($useIPv6) {
            $serverAddresses += '::1'
        }

        # Keep the existing resolvers as emergency fallbacks. This avoids
        # losing DNS if the local service stops during or after installation.
        $serverAddresses += @(
            $backup.ServerAddresses |
                Where-Object { $_ -notin @('127.0.0.1', '::1') }
        )

        Set-DnsClientServerAddress `
            -InterfaceIndex $adapter.ifIndex `
            -ServerAddresses ($serverAddresses | Select-Object -Unique) `
            -ErrorAction Stop

        Write-OK "$($adapter.Name)"
    }

    # Flush Windows DNS cache after the change.
    ipconfig /flushdns | Out-Null

    Start-Sleep -Seconds 2

    # -----------------------------------------------------------------------
    # Verify the actual system resolver path.
    # -----------------------------------------------------------------------

    Write-Host ""
    Write-Host "Verifying DNS after cutover..."

    $systemDnsOK = $false

    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            $result = Resolve-DnsName `
                -Name "example.com" `
                -Type A `
                -DnsOnly `
                -ErrorAction Stop

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

    Restore-DnsConfiguration -DnsBackup $dnsBackup

    Write-Host ""
    Write-Host "The original DNS configuration has been restored." `
        -ForegroundColor Green

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

#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Downloads Steven Black's unified hosts file, compresses it for Windows performance,
    and applies it to C:\Windows\System32\drivers\etc\hosts.

.DESCRIPTION
    Uses hosts-compress-windows (auto-downloaded) to compress the hosts file,
    which significantly improves DNS lookup performance on Windows when the
    DNS Client service is enabled.

    Steven Black variants (edit $HOSTS_URL to choose):
      Unified (ads + malware):       https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
      + Fakenews:                    https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews/hosts
      + Gambling:                    https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/gambling/hosts
      + Porn:                        https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn/hosts
      + Fakenews + Gambling + Porn:  https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn/hosts
      + All above + Social:         https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn-social/hosts

.NOTES
    Run from an elevated PowerShell prompt.
    A backup of the previous hosts file is saved alongside it as hosts.bak.
    Reddit and Twitter/X sections are commented out so they remain accessible.
#>

# --- Config ---
$HOSTS_URL = 'https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn-social/hosts'
$HOSTS_DST = "$env:SystemRoot\System32\drivers\etc\hosts"
$TOOL_DIR  = "$env:LOCALAPPDATA\hosts-compress-windows"

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- 1. Download hosts-compress-windows if not cached ---
$compressExe = Join-Path $TOOL_DIR "hostscompress.exe"

if (-not (Test-Path $compressExe)) {
    Write-Host ""
    Write-Host "[1/4] Downloading hosts-compress-windows..."
    $release = Invoke-RestMethod "https://api.github.com/repos/Lateralus138/hosts-compress-windows/releases/latest"
    $asset   = $release.assets | Where-Object { $_.name -match '\.exe$' } | Select-Object -First 1

    if (-not $asset) {
        throw "Could not find an .exe asset in the hosts-compress-windows release."
    }

    New-Item -ItemType Directory -Force -Path $TOOL_DIR | Out-Null
    curl.exe -sSL --retry 3 -o $compressExe $asset.browser_download_url
    Write-Host "  Downloaded $($asset.name)"
} else {
    Write-Host ""
    Write-Host "[1/4] hosts-compress-windows already cached."
}

# --- 2. Download Steven Black's hosts file ---
Write-Host ""
Write-Host "[2/4] Downloading Steven Black's unified hosts file..."
$rawHosts = "$env:TEMP\steven-black-hosts.txt"

# curl.exe (built-in on Win10/11) handles network restrictions better than Invoke-WebRequest
curl.exe -sSL --retry 3 -o $rawHosts $HOSTS_URL
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $rawHosts) -or (Get-Item $rawHosts).Length -eq 0) {
    throw "Failed to download hosts file from $HOSTS_URL (curl exit code $LASTEXITCODE)"
}

$lineCount = (Get-Content $rawHosts).Count
Write-Host "  Downloaded: $lineCount lines."

# --- 2.5. Comment out Reddit and Twitter/X sections ---
Write-Host ""
Write-Host "[2.5/4] Commenting out Reddit and Twitter/X sections..."
$lines = Get-Content $rawHosts
$result = [System.Collections.Generic.List[string]]::new()
$inSection = $false

foreach ($line in $lines) {
    if ($line -match '^# (Reddit|Twitter)$') {
        $inSection = $true
        $result.Add("# $line")
        continue
    }
    if ($inSection -and $line -match '^[0-9]') {
        $result.Add("# $line")
        continue
    }
    if ($inSection -and $line -match '^#') {
        $inSection = $false
    }
    $result.Add($line)
}

$result | Set-Content $rawHosts -Encoding UTF8
Write-Host "  Reddit and Twitter/X sections commented out (will be excluded from compressed output)."

# --- 3. Compress ---
Write-Host ""
Write-Host "[3/4] Compressing (9 domains per line, stripping comments)..."
$compressed = "$env:TEMP\hosts-compressed.txt"

# /i = input, /o = output, /d = discard non-compressed lines, /c 9 = 9 URLs per line
& $compressExe /i $rawHosts /o $compressed /d /c 9

$compressedLines = (Get-Content $compressed).Count
Write-Host "  Result: $lineCount -> $compressedLines lines"

# --- 4. Backup & apply ---
Write-Host ""
Write-Host "[4/4] Applying hosts file..."
$backup = "$HOSTS_DST.bak"
Copy-Item $HOSTS_DST $backup -Force
Write-Host "  Backed up existing hosts -> $backup"

Copy-Item $compressed $HOSTS_DST -Force
Write-Host "  Applied new hosts file."

ipconfig /flushdns | Out-Null
Write-Host "  DNS cache flushed."

Write-Host ""
Write-Host "Done! Hosts file updated with Steven Black's fakenews+gambling+porn+social blocklist."
Write-Host "  Reddit and Twitter/X are NOT blocked."
Write-Host "  Lines: $compressedLines (was $lineCount before compression)"

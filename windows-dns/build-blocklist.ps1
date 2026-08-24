<#
.SYNOPSIS
    Builds blocked-names.generated.txt from blocked-names.txt plus a remote hosts blocklist.

.DESCRIPTION
    Converts a hosts-format blocklist (default: Steven Black unified plus
    fakenews, gambling, porn and social) into plain domain rules for
    dnscrypt-proxy, appends them to the local blocked-names.txt rules, and
    writes the merged result to blocked-names.generated.txt.

    Imported names inside a zone already covered by blocked-names.txt are
    dropped, so scheduled rules such as X and Reddit keep their schedule instead
    of being blocked unconditionally by the imported list.

.NOTES
    Does not require administrator rights; it only writes into this directory.
#>

[CmdletBinding()]
param(
    [string]$HostsUrl = 'https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn-social/hosts',
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $OutputPath) {
    $OutputPath = Join-Path $PSScriptRoot 'blocked-names.generated.txt'
}

$customPath = Join-Path $PSScriptRoot 'blocked-names.txt'

if (-not (Test-Path $customPath)) {
    throw "blocked-names.txt was not found at $customPath."
}

$customLines = Get-Content $customPath
$customRules = $customLines |
    ForEach-Object { ($_ -replace '#.*$', '').Trim() } |
    Where-Object { $_ -ne '' } |
    ForEach-Object { ($_ -split '\s+')[0].ToLowerInvariant() }

# Zones owned by blocked-names.txt: imported names inside them are dropped so the
# local rule (and its schedule) stays authoritative.
$ownedZones = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]($customRules |
        Where-Object { $_ -notmatch '\*\.\*' } |
        ForEach-Object { $_.TrimStart('=') -replace '^\*\.', '' } |
        Where-Object { $_ -match '^[a-z0-9.-]+\.[a-z0-9-]+$' }),
    [System.StringComparer]::OrdinalIgnoreCase
)

Write-Host "Downloading $HostsUrl ..."
$rawPath = Join-Path ([System.IO.Path]::GetTempPath()) 'dnscrypt-hosts-source.txt'
curl.exe -sSL --retry 3 -o $rawPath $HostsUrl

if ($LASTEXITCODE -ne 0 -or -not (Test-Path $rawPath) -or (Get-Item $rawPath).Length -eq 0) {
    throw "Failed to download $HostsUrl (curl exit code $LASTEXITCODE)."
}

$domains = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$hostsLine = [regex]'^\s*(?:0\.0\.0\.0|127\.0\.0\.1|::1)\s+(?<name>[A-Za-z0-9._-]+\.[A-Za-z0-9-]+)\s*(?:#.*)?$'
$skipNames = @('localhost', 'localhost.localdomain', 'local', 'broadcasthost')

foreach ($line in [System.IO.File]::ReadLines($rawPath)) {
    $match = $hostsLine.Match($line)

    if (-not $match.Success) { continue }

    $name = $match.Groups['name'].Value.TrimEnd('.').ToLowerInvariant()

    if ($skipNames -contains $name) { continue }

    $owned = $false
    $zone = $name

    while ($zone) {
        if ($ownedZones.Contains($zone)) {
            $owned = $true
            break
        }

        $dot = $zone.IndexOf('.')
        $zone = if ($dot -lt 0) { '' } else { $zone.Substring($dot + 1) }
    }

    if ($owned) { continue }

    [void]$domains.Add($name)
}

if ($domains.Count -eq 0) {
    throw "No domains were parsed from $HostsUrl; refusing to write an empty blocklist."
}

$header = @(
    '###########################################################',
    '# GENERATED FILE -- do not edit.',
    '# Edit blocked-names.txt, then run build-blocklist.ps1.',
    "# Source: $HostsUrl",
    "# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    '###########################################################',
    ''
)

$output = [System.Collections.Generic.List[string]]::new()
$output.AddRange([string[]]$header)
$output.AddRange([string[]]$customLines)
$output.Add('')
$output.Add('###########################')
$output.Add('#   Imported hosts list   #')
$output.Add('###########################')
$output.AddRange([string[]]$domains)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines($OutputPath, $output, $utf8NoBom)

Write-Host "Wrote $OutputPath"
Write-Host "  Custom rules:   $($customRules.Count)"
Write-Host "  Imported names: $($domains.Count)"

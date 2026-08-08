#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Restores the previous Windows hosts file backup.

.DESCRIPTION
    Restores C:\Windows\System32\drivers\etc\hosts from hosts.bak.

.NOTES
    Run from an elevated PowerShell prompt.
    This script expects update-hosts.ps1 to have created hosts.bak.
#>

$HOSTS_DST = "$env:SystemRoot\System32\drivers\etc\hosts"
$BACKUP    = "$HOSTS_DST.bak"
$DEFAULT_HOSTS = @"
# Copyright (c) 1993-2009 Microsoft Corp.
#
# This is a sample HOSTS file used by Microsoft TCP/IP for Windows.
#
# This file contains the mappings of IP addresses to host names. Each
# entry should be kept on an individual line. The IP address should
# be placed in the first column followed by the corresponding host name.
# The IP address and the host name should be separated by at least one
# space.
#
# Additionally, comments (such as these) may be inserted on individual
# lines or following the machine name denoted by a # symbol.
#
# For example:
#
#      102.54.94.97     rhino.acme.com          # source server
#       38.25.63.10     x.acme.com              # x client host

# localhost name resolution is handled within DNS itself.
#	127.0.0.1       localhost
#	::1             localhost
"@

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "[1/2] Restoring hosts backup..."

if (Test-Path $BACKUP) {
    Copy-Item $BACKUP $HOSTS_DST -Force
    Write-Host "  Restored $HOSTS_DST from backup."
} else {
    Set-Content -Path $HOSTS_DST -Value $DEFAULT_HOSTS -Encoding ASCII
    Write-Warning "Hosts backup not found. Wrote default Windows hosts file instead."
}

Write-Host ""
Write-Host "[2/2] Flushing DNS cache..."
ipconfig /flushdns | Out-Null

Write-Host ""
Write-Host "Done! Original hosts file restored."

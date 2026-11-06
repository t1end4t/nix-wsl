[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$archive = Join-Path $PSScriptRoot 'archives/original-files.zip'
$destination = Join-Path $PSScriptRoot 'payload'
if (Test-Path -LiteralPath $destination) {
    throw 'payload already exists. Keep it or rename it before restoring again; existing files will not be overwritten.'
}
if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
    throw "Archive not found: $archive"
}
Expand-Archive -LiteralPath $archive -DestinationPath $destination
Write-Output "Restored original files to $destination. No repair script was executed."

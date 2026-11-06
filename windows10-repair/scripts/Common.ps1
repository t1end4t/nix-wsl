# Shared paths for scripts stored one group below this directory.
$RepairRoot = Split-Path $PSScriptRoot -Parent
$RepairPayload = Join-Path $RepairRoot 'payload'

. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Common.ps1')
Get-ChildItem "$env:LOCALAPPDATA\Microsoft", "$env:LOCALAPPDATA\Packages" -Filter settings.json -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match 'Terminal' } | ForEach-Object { $_.FullName; Get-Content $_.FullName }

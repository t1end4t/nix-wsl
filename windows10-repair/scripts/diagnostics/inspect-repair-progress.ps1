. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Common.ps1')
Get-Content C:\Windows\Logs\DISM\dism.log -Tail 18
Get-ChildItem C:\Windows\WinSxS\Manifests -Filter '*powershell*' -ErrorAction SilentlyContinue | Select-Object -First 5 -ExpandProperty Name

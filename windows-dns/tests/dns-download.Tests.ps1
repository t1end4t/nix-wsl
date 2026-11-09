# No network requests or installation changes: GitHub responses are mocked.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'dns-download.ps1')

function Assert-True($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$script:Scenario = ''
$script:Requests = [System.Collections.Generic.List[string]]::new()
function Invoke-RestMethod {
    param($Uri,$Headers,$TimeoutSec,$ErrorAction)
    $script:Requests.Add('api')
    if ($script:Scenario -ne 'api-success' -and $script:Scenario -ne 'missing-asset') {
        throw 'API rate limit exceeded.'
    }
    $assets = @(
        [pscustomobject]@{name='dnscrypt-proxy-win32-2.1.20.zip';browser_download_url='https://github.com/DNSCrypt/dnscrypt-proxy/releases/download/2.1.20/dnscrypt-proxy-win32-2.1.20.zip'}
    )
    if ($script:Scenario -eq 'api-success') {
        $assets += [pscustomobject]@{name='dnscrypt-proxy-win64-2.1.20.zip';browser_download_url='https://github.com/DNSCrypt/dnscrypt-proxy/releases/download/2.1.20/dnscrypt-proxy-win64-2.1.20.zip'}
    }
    [pscustomobject]@{tag_name='2.1.20';assets=$assets}
}
function Invoke-WebRequest {
    param($Uri,$Method,[switch]$UseBasicParsing,$TimeoutSec,$ErrorAction)
    if ($Uri -like '*/releases/latest') {
        $script:Requests.Add('latest')
        if ($script:Scenario -eq 'both-fail') { throw 'Public GitHub page unavailable.' }
        $tagUri = if ($script:Scenario -eq 'bad-redirect') {
            [uri]'https://example.com/DNSCrypt/dnscrypt-proxy/releases/tag/2.1.20'
        } else { [uri]'https://github.com/DNSCrypt/dnscrypt-proxy/releases/tag/2.1.20' }
        if ($script:Scenario -eq 'powershell-5') {
            return [pscustomobject]@{BaseResponse=[pscustomobject]@{ResponseUri=$tagUri}}
        }
        return [pscustomobject]@{BaseResponse=[pscustomobject]@{RequestMessage=[pscustomobject]@{RequestUri=$tagUri}}}
    }
    Assert-True ($Uri -eq 'https://github.com/DNSCrypt/dnscrypt-proxy/releases/expanded_assets/2.1.20') 'Unexpected asset endpoint.'
    $script:Requests.Add('assets')
    $content = '<a href="/DNSCrypt/dnscrypt-proxy/releases/download/2.1.20/dnscrypt-proxy-win32-2.1.20.zip">32 bit</a>'
    if ($script:Scenario -ne 'no-windows-asset') {
        $tag = if ($script:Scenario -eq 'wrong-tag') { '2.1.19' } else { '2.1.20' }
        $content += "<a href=`"/DNSCrypt/dnscrypt-proxy/releases/download/$tag/dnscrypt-proxy-win64-2.1.20.zip`">64 bit</a>"
    }
    [pscustomobject]@{Content=$content}
}

foreach ($scenario in @('api-success','rate-limited','missing-asset','powershell-5','both-fail','bad-redirect','no-windows-asset','wrong-tag')) {
    $script:Scenario = $scenario
    $script:Requests.Clear()
    $caught = $null; $asset = $null
    try { $asset = Get-DnscryptReleaseAsset } catch { $caught = $_ }
    if ($scenario -in @('api-success','rate-limited','missing-asset','powershell-5')) {
        Assert-True (-not $caught) "Discovery failed for $scenario : $caught"
        Assert-True ($asset.TagName -eq '2.1.20') 'Wrong release tag.'
        Assert-True ($asset.Name -eq 'dnscrypt-proxy-win64-2.1.20.zip') 'Wrong asset architecture.'
        Assert-True ($asset.DownloadUrl -eq 'https://github.com/DNSCrypt/dnscrypt-proxy/releases/download/2.1.20/dnscrypt-proxy-win64-2.1.20.zip') 'Wrong download URL.'
        $expected = if ($scenario -eq 'api-success') { 'api' } else { 'api,latest,assets' }
        Assert-True (($script:Requests -join ',') -eq $expected) 'Unexpected request sequence.'
    } else {
        Assert-True ([bool]$caught) "Discovery should fail for $scenario"
        Assert-True ($caught.ToString() -match 'No service or Windows DNS settings have been changed') 'Missing safe-failure guidance.'
    }
    Write-Output "PASS: $scenario"
}
Write-Output 'All release discovery tests passed.'

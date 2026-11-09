# Release discovery helpers. Dot-sourcing this file performs no network requests.

function New-DnscryptReleaseAsset {
    param([string]$TagName, [string]$Name, [string]$DownloadUrl)

    $uri = [uri]$DownloadUrl
    $prefix = '/DNSCrypt/dnscrypt-proxy/releases/download/' + [uri]::EscapeDataString($TagName) + '/'
    if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'https' -or $uri.Host -ne 'github.com' -or
        -not $uri.AbsolutePath.StartsWith($prefix, [System.StringComparison]::Ordinal) -or
        $Name -notmatch '^dnscrypt-proxy-win64-[^/]+\.zip$' -or
        [uri]::UnescapeDataString(($uri.AbsolutePath -split '/')[-1]) -ne $Name) {
        throw 'The release did not provide an official Windows x64 ZIP download.'
    }
    [pscustomobject]@{ TagName = $TagName; Name = $Name; DownloadUrl = $uri.AbsoluteUri }
}

function Get-DnscryptReleaseAsset {
    $repository = 'https://github.com/DNSCrypt/dnscrypt-proxy'
    try {
        $release = Invoke-RestMethod `
            -Uri 'https://api.github.com/repos/DNSCrypt/dnscrypt-proxy/releases/latest' `
            -Headers @{ Accept = 'application/vnd.github+json'; 'User-Agent' = 'dnscrypt-proxy-windows-setup' } `
            -TimeoutSec 30 -ErrorAction Stop
        $asset = $release.assets |
            Where-Object { $_.name -match '^dnscrypt-proxy-win64-[^/]+\.zip$' } |
            Select-Object -First 1
        if (-not $asset) { throw 'No Windows x64 ZIP was listed by the release API.' }
        return New-DnscryptReleaseAsset -TagName $release.tag_name -Name $asset.name `
            -DownloadUrl $asset.browser_download_url
    }
    catch {
        Write-Warning 'GitHub release API unavailable. Checking the public release page instead (no token required).'
    }

    try {
        # GitHub's public latest-release redirect is independent of REST API quotas.
        $response = Invoke-WebRequest -Uri "$repository/releases/latest" -Method Head `
            -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        $baseResponse = $response.BaseResponse
        $latestUri = if ($baseResponse.PSObject.Properties['ResponseUri']) {
            [uri]$baseResponse.ResponseUri # Windows PowerShell 5.1
        } else {
            [uri]$baseResponse.RequestMessage.RequestUri # PowerShell 7
        }
        if ($latestUri.Scheme -ne 'https' -or $latestUri.Host -ne 'github.com' -or
            $latestUri.AbsolutePath -notmatch '^/DNSCrypt/dnscrypt-proxy/releases/tag/(?<tag>[^/]+)$') {
            throw 'GitHub did not redirect to an official tagged release.'
        }
        $tagName = [uri]::UnescapeDataString($Matches.tag)
        # GitHub loads release asset links separately from the main release page.
        $assetsPage = Invoke-WebRequest `
            -Uri "$repository/releases/expanded_assets/$([uri]::EscapeDataString($tagName))" `
            -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        $assetLinks = [regex]::Matches($assetsPage.Content,
            'href="(?<path>/DNSCrypt/dnscrypt-proxy/releases/download/[^"/]+/dnscrypt-proxy-win64-[^"/]+\.zip)"')
        foreach ($link in $assetLinks) {
            $path = [System.Net.WebUtility]::HtmlDecode($link.Groups['path'].Value)
            $name = [uri]::UnescapeDataString(($path -split '/')[-1])
            return New-DnscryptReleaseAsset -TagName $tagName -Name $name -DownloadUrl "https://github.com$path"
        }
        throw 'No Windows x64 ZIP was found on the public release page.'
    }
    catch {
        throw "Could not find the latest Windows x64 dnscrypt-proxy release through the API or public release page. $($_.Exception.Message) No service or Windows DNS settings have been changed."
    }
}

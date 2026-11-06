. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Common.ps1')
$ErrorActionPreference = 'Continue'
'Windows version:'
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' | Select-Object ProductName,ReleaseId,CurrentBuild,UBR | Format-List
'Capture components:'
foreach ($capturePath in @('C:\Windows\System32\ScreenClippingHost.exe','C:\Windows\SystemApps\Microsoft.Windows.ShellExperienceHost_cw5n1h2txyewy\ScreenClippingHost.exe','C:\Windows\System32\SnippingTool.exe')) {
 [pscustomobject]@{Path=$capturePath;Exists=(Test-Path -LiteralPath $capturePath)}
}
'Capture registrations:'
Get-ChildItem 'Registry::HKEY_CLASSES_ROOT\Extensions\ContractId\Windows.Protocol\PackageId' -ErrorAction SilentlyContinue | Where-Object PSChildName -Match 'ScreenSketch|ShellExperience' | Select-Object PSChildName
'Recent capture errors:'
try { Get-WinEvent -FilterHashtable @{LogName='Application';StartTime=(Get-Date).AddHours(-2);Level=2} -MaxEvents 30 -ErrorAction Stop | Where-Object Message -Match 'ScreenClipping|SnippingTool|ScreenSketch|ChatGPT|clipboard' | Select-Object TimeCreated,ProviderName,Message | Format-List } catch { $_.Exception.Message }
'Browser and editor versions:'
Get-Process firefox,msedge,Code -ErrorAction SilentlyContinue | Group-Object ProcessName | ForEach-Object { $_.Group | Select-Object -First 1 ProcessName,Path,@{n='Version';e={$_.MainModule.FileVersionInfo.ProductVersion}} } | Format-List

# Windows DNS setup troubleshooting

## GitHub API rate limit at step 2

If GitHub returns `API rate limit exceeded`, rerun the updated `setup-dns.ps1`.
The installer first tries the release API, then follows GitHub's public
`releases/latest` redirect and reads the release's asset links if the API fails.
The fallback needs no GitHub token and selects the official Windows x64 ZIP
for that release. If both discovery methods fail, setup stops before service
or DNS changes. It does not disable certificate verification or use mirrors.

```powershell
pwsh -NoProfile -File .\tests\dns-download.Tests.ps1
```

## Missing Windows networking cmdlets

Earlier versions of `setup-dns.ps1` stopped at `[0/7]` when `Resolve-DnsName`,
`Get-NetAdapter`, `Get-DnsClientServerAddress`, or `Set-DnsClientServerAddress`
was unavailable. That dependency check stopped installation before service
or adapter DNS changes. The current installer supports stripped Windows without
restoring those modules.

## Install on stripped Windows

Run the updated installer from an elevated 64-bit PowerShell 7 session:

```powershell
.\setup-dns.ps1
```

When networking cmdlets are missing, a warning announces the fallback to CIM,
.NET and `netsh.exe`. Windows PowerShell is not required for this path.
`Get-CimInstance`, access to `Win32_NetworkAdapter`, the Windows networking
registry keys, and `netsh.exe`/`ipconfig.exe` must still work. Missing prerequisites
or unreadable DNS snapshots stop installation before service or DNS changes.

The installer probes `127.0.0.1:53` and, when configured, `[::1]:53` directly
with DNS queries. It switches only verified listeners, leaves IPv6 unchanged
when its listener is unavailable, and checks Windows resolution plus HTTPS
after cutover. If a write or verification fails, rollback restores each changed
IP family's original static list or automatic DNS mode. An incomplete rollback
is reported explicitly, with the proxy service left running.

Read-only backend inspection (no DNS writes):

```powershell
. .\dns-network.ps1
Initialize-DnsNetworking
Get-DnsSetupAdapters | ForEach-Object { Get-DnsSetupConfiguration -Adapter $_ }
```

Regression checks use local UDP fixtures and mocked adapter writes:

```powershell
pwsh -NoProfile -File .\tests\dns-network.Tests.ps1
```

## Optional: restore Windows modules

Check the Windows modules from a 64-bit PowerShell session:

```powershell
Test-Path "$env:windir\System32\WindowsPowerShell\v1.0\Modules"
Get-Module -ListAvailable DnsClient, NetAdapter
Get-Command Resolve-DnsName, Get-NetAdapter, Get-DnsClientServerAddress, Set-DnsClientServerAddress
```

If the modules exist, try importing them in elevated Windows PowerShell.
Import errors can identify dependencies or module discovery problems:

```powershell
Import-Module DnsClient -ErrorAction Stop
Import-Module NetAdapter -ErrorAction Stop
```

If the directory or modules are missing, installing PowerShell 7 does not
restore these Windows components. On stripped Windows installations, the
Windows component store may also lack the files needed to recover them.

Microsoft's system-file repair procedure starts with these commands in an
elevated terminal. Run SFC after DISM completes successfully:

```powershell
DISM.exe /Online /Cleanup-Image /RestoreHealth
sfc.exe /scannow
```

See [Microsoft's repair instructions](https://support.microsoft.com/en-us/windows/experience/backup-recovery/use-the-system-file-checker-tool-to-repair-missing-or-corrupted-system-files).
If DISM cannot find repair files, use a compatible Windows repair source;
see [Repair a Windows image](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/repair-a-windows-image).
These repairs are not guaranteed to restore components removed by a custom
Windows image. Keep the repair output to diagnose the next step.

If Windows PowerShell itself is missing, the module import commands above
cannot restore it. DISM error `0x800f081f` means the repair source is missing;
repeating the same command without a usable source will not supply those files.
Use compatible installation media and the correct image index as described in
[Configure a Windows repair source](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/configure-a-windows-repair-source).

After repair, open a fresh elevated PowerShell session and repeat the command
checks above. If all four commands are available, setup selects the cmdlet path;
otherwise it continues to use the native fallback.

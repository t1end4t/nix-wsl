# Windows DNS

Windows `dnscrypt-proxy` installation, filtering, and migration utilities.

- `setup-dns.ps1`: installs and configures the service.
- `dns-network.ps1`: setup networking helpers, including the stripped-Windows fallback.
- `dns-download.ps1`: release discovery with a public-page fallback for GitHub API failures.
- `update-dns.ps1`: rebuilds filtering data and restarts the service.
- `build-blocklist.ps1`: merges `blocked-names.txt` with the StevenBlack unified list.
- `dnscrypt-proxy.toml`: service configuration.
- `blocked-names.txt`: custom and scheduled blocking rules.
- `allowed-names.txt`: blocking exceptions.
- `cloaking-rules.txt`: DNS aliases and safe-search rules.
- `uninstall-hosts.ps1`: restores the hosts file after migration.
- `uninstall-dns.ps1`: removes the DNS service setup.
- `TROUBLESHOOTING.md`: networking prerequisites and optional Windows component repair.
- `tests/dns-network.Tests.ps1`: local DNS probes and simulated cutover/rollback tests.
- `tests/dns-download.Tests.ps1`: release API and public-page fallback tests.

Run `setup-dns.ps1` from an elevated 64-bit PowerShell session. PowerShell 7
works even if Windows PowerShell and the DnsClient/NetAdapter modules were removed.
The installer automatically uses CIM, .NET and `netsh.exe` when any required
networking cmdlet is unavailable. It checks adapter access and DNS snapshots
before installing, verifies each local listener before cutover, and preserves
automatic versus static DNS separately for IPv4 and IPv6 during rollback.
Previous DNS servers remain configured as fallbacks; they can bypass filtering
if the local resolver is unavailable.

Run `uninstall-dns.ps1` from an elevated PowerShell prompt. If the NetAdapter
or DnsClient cmdlets are unavailable, it uses CIM and `netsh.exe` to reset DNS
for both IP families. It backs up static DNS settings before changing adapters
and attempts to restore them if reset or DNS verification fails, leaving the
service running. CIM and the Windows networking executables must be available.

Operating rules: `AGENTS.md`.

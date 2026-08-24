# Windows DNS

Windows `dnscrypt-proxy` installation, filtering, and migration utilities.

- `setup-dns.ps1`: installs and configures the service.
- `update-dns.ps1`: rebuilds filtering data and restarts the service.
- `build-blocklist.ps1`: merges `blocked-names.txt` with the StevenBlack unified list.
- `dnscrypt-proxy.toml`: service configuration.
- `blocked-names.txt`: custom and scheduled blocking rules.
- `allowed-names.txt`: blocking exceptions.
- `cloaking-rules.txt`: DNS aliases and safe-search rules.
- `uninstall-hosts.ps1`: restores the hosts file after migration.
- `uninstall-dns.ps1`: removes the DNS service setup.

Operating rules: `AGENTS.md`.

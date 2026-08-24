# Windows DNS Operations

- Run `setup-dns.ps1`, `update-dns.ps1`, and uninstall scripts from elevated Windows PowerShell.
- Edit custom filtering in `blocked-names.txt`; never edit `blocked-names.generated.txt`.
- Run `build-blocklist.ps1` after changing custom rules. The generated file is intentionally ignored by Git.
- Keep the Windows hosts file minimal. Use `uninstall-hosts.ps1` once when migrating from the old hosts-based blocklist.
- Validate PowerShell syntax and run `dnscrypt-proxy.exe -check` before changing the service configuration.
- See `INDEX.md` for the file map.

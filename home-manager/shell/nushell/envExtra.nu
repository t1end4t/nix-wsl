# source: https://github.com/atuinsh/atuin?tab=readme-ov-file#nushell
atuin init nu | save -f ~/.local/share/atuin/init.nu

# source: https://github.com/ajeetdsouza/zoxide
zoxide init nushell | save -f ~/.zoxide.nu

# manual setup github token
if ("~/.config/environment.d/github.conf" | path exists) {
  $env.GITHUB_PERSONAL_ACCESS_TOKEN = (open ~/.config/environment.d/github.conf | parse "{key}={value}" | where key == "GITHUB_PERSONAL_ACCESS_TOKEN" | get value | first)
}

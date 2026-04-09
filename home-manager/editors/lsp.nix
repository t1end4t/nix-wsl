{ pkgs, ... }:
{
  home.packages = with pkgs; [
    nil # lsp for nix
    nodePackages.bash-language-server # lsp for sh
    markdown-oxide # lsp for markdown

    # formatters
    nixfmt-rfc-style
    taplo # toml
    deno # web-related
    prettierd # other web-related
  ];
}

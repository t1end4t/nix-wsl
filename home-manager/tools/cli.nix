{ pkgs, ... }:
{
  home.packages = with pkgs; [
    fd
    zoxide
    ripgrep
    eza
    dust
    silver-searcher
    tldr
    atuin
    trash-cli
    just
    unzip
    nh
    neofetch
    unar
    gh
  ];

  programs.bat.enable = true;
}

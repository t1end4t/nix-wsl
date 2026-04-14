{
  imports = [
    ./base.nix
    ./ai-tools.nix
    ./environment.nix
    ./editors
    ./shell
    ./tools
    ./gui/zellij/zellij.nix
    ./gui/catppuccin.nix
  ];

  home.username = "tiendat";
  home.homeDirectory = "/home/tiendat";
}

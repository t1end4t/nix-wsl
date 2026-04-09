{
  imports = [
    ./base.nix
    ./environment.nix
    ./editors
    ./shell
    ./tools
    ./ai-tools/ai-tools.nix
    ./gui/zellij/zellij.nix
    ./gui/catppuccin.nix
  ];

  home.username = "tiendat";
  home.homeDirectory = "/home/tiendat";
}

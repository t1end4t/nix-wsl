# WSL home-manager configuration
# Imports reusable modules from nixos-conf submodule.
# Excluded: desktop-apps, gui (hyprland/wayland stack), research/local-llm (CUDA)
{
  imports = [
    ../nixos-conf/home-manager/base.nix
    ./environment.nix
    ../nixos-conf/home-manager/editors
    ../nixos-conf/home-manager/shell
    ../nixos-conf/home-manager/tools
    ../nixos-conf/home-manager/ai-tools/ai-tools.nix
    ../nixos-conf/home-manager/gui/zellij/zellij.nix
    ../nixos-conf/home-manager/gui/catppuccin.nix
  ];

  home.username = "tiendat";
  home.homeDirectory = "/home/tiendat";

  # gnome-keyring requires a desktop session on WSL; disable it
  services.gnome-keyring.enable = false;
}

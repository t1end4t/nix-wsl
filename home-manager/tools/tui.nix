{ pkgs, ... }:
{
  home.packages = with pkgs; [
    lazydocker
  ];

  programs = {
    lazygit.enable = true;
    btop.enable = true;
  };
}

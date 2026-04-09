{ pkgs, ... }:
let
  ROOT = builtins.toString ./.;
in
{
  home.packages = with pkgs; [
    zellij
  ];

  home.file.".config/zellij/config.kdl" = {
    source = "${ROOT}/config.kdl";
  };
}

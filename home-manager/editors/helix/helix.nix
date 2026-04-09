{ pkgs, ... }:
let
  ROOT = builtins.toString ./.;
  stripCR = s: builtins.replaceStrings [ "\r" ] [ "" ] s;
  settings_toml = stripCR (builtins.readFile "${ROOT}/config.toml");
  languages_toml = stripCR (builtins.readFile "${ROOT}/languages.toml");
in
{
  programs.helix = {
    enable = true;
    package = pkgs.unstable.helix;
    defaultEditor = true;
    settings = builtins.fromTOML settings_toml;
    languages = builtins.fromTOML languages_toml;
  };

  home.packages = with pkgs; [
    harper # grammar checker
  ];

  catppuccin.helix.useItalics = true;
}

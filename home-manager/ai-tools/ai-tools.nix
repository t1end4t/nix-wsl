{ pkgs, ... }:
let
  ROOT = builtins.toString ./.;
in
{
  home.packages = with pkgs; [
    nodejs
    bun
    python313
    uv
  ];

  home.file.".aider.conf.yml.gpg" = {
    source = "${ROOT}/secrets/aider.conf.yml.gpg";
  };

  home.file.".claude-code-router/config.json.gpg" = {
    source = "${ROOT}/secrets/claude-code-router-config.json.gpg";
  };
}

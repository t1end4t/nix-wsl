{ nushell-defaultConfig, ... }:
let
  extraConfig = builtins.readFile ./configExtra.nu;
  ROOT = builtins.toString ./.;
in
{
  programs.nushell = {
    enable = true;
    configFile.source = "${nushell-defaultConfig}/crates/nu-utils/src/default_files/default_config.nu";
    envFile.source = "${nushell-defaultConfig}/crates/nu-utils/src/default_files/default_env.nu";
    extraConfig = ''
      ${extraConfig}
    '';
    extraEnv = builtins.readFile ./envExtra.nu;
  };
}

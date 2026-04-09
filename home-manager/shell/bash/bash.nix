{
  programs.bash = {
    enable = true;
    bashrcExtra = builtins.replaceStrings [ "\r" ] [ "" ] (builtins.readFile ./bashrc);
  };
}

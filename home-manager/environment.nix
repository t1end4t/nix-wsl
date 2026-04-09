# WSL-specific session variables
# Overrides nixos-conf/home-manager/environment.nix (not imported from there)
_: {
  home.sessionVariables = {
    EDITOR = "hx";
    # BROWSER intentionally unset — no GUI browser on WSL
    # GTK_IM_MODULE / QT_IM_MODULE not needed without a desktop session
  };
}

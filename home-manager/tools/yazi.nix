{ pkgs, ... }:
{
  home.packages = with pkgs; [
    file
    ffmpegthumbnailer
    unar
    jq
    poppler
  ];

  programs.yazi.enable = true;
}

{
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "t1end4t";
        email = "tiendatarse3004@gmail.com";
      };
      submodule.recurse = true;
    };
    lfs.enable = true;
  };
}

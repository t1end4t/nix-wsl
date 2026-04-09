{
  description = "Home Manager config for NixOS WSL";

  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://devenv.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin.url = "github:catppuccin/nix/release-25.11";

    nushell-defaultConfig = {
      url = "github:nushell/nushell";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      catppuccin,
      nushell-defaultConfig,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      outputs = self;

      # Exposed so home-manager/base.nix can reference outputs.overlays.*
      overlays = {
        additions = _final: _prev: { };
        modifications = _final: _prev: { };
        unstable-packages = final: _prev: {
          unstable = import inputs.nixpkgs-unstable {
            system = final.stdenv.hostPlatform.system;
            config.allowUnfree = true;
          };
        };
      };
    in
    {
      inherit overlays;

      formatter.${system} = nixpkgs.legacyPackages.${system}.alejandra;

      # Apply with: home-manager switch --flake .#tiendat
      homeConfigurations."tiendat" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.${system};
        extraSpecialArgs = {
          inherit
            inputs
            outputs
            nushell-defaultConfig
            ;
        };
        modules = [
          ./home-manager/wsl.nix
          catppuccin.homeModules.catppuccin
        ];
      };
    };
}

{
  description = "A simple NixOS flake";

  inputs = {
    # NixOS official package source, using the nixos-23.11 branch here
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    # NixOS official package source, using the unstable branch here
    unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    # home-manager, used for managing user configuration
    home-manager = {
      url = "github:nix-community/home-manager/release-23.11";
      # The `follows` keyword in inputs is used for inheritance.
      # Here, `inputs.nixpkgs` of home-manager is kept consistent with
      # the `inputs.nixpkgs` of the current flake,
      # to avoid problems caused by different versions of nixpkgs.
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, unstable, home-manager }:
  let
    overlay = final: prev: let
      unstablePkgs = import unstable { inherit (prev) system; config.allowUnfree = true; };
    in {
      unstable = unstablePkgs;
    };
    # Overlays-module makes "pkgs.unstable" available in configuration.nix
    overlayModule = ({ config, pkgs, ... }: {
      nixpkgs.overlays = [ overlay ];
    });
    # To generate host configurations for all hosts.
    hostnames = builtins.attrNames (builtins.readDir ./hosts);
  in {
    nixosConfigurations = builtins.listToAttrs (builtins.map (host: {
      name = host;
      value = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs.channels = { inherit nixpkgs unstable; };
        modules = [
          overlayModule
          ./hosts/${host}/configuration.nix

          # make home-manager as a module of nixos
          # so that home-manager configuration will be deployed automatically when executing `nixos-rebuild switch`
          home-manager.nixosModules.home-manager {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.nils = import ./home.nix;
            # Optionally, use home-manager.extraSpecialArgs to pass arguments to home.nix
          }
        ];
      };
    }) hostnames);
  };
}

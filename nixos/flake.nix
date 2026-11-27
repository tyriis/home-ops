{
  description = "NixOS hosts of the techtales docker-lane fleet (pilot per #11792 spec 2026-11-07)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    {
      nixosConfigurations = {
        bifrost = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./modules/docker-lane.nix
            ./modules/hardening.nix
            ./hosts/bifrost.nix
          ];
        };
        bifrostix = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./modules/docker-lane.nix
            ./modules/hardening.nix
            ./hosts/bifrostix.nix
          ];
        };
      };
    };
}

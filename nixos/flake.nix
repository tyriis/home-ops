{
  description = "NixOS hosts of the techtales docker-lane fleet (pilot per #11792 spec 2026-11-07)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/f1e5c356f35d07e7b71a6b5e6c9338e0b029e0c0";
  };

  outputs =
    { self, nixpkgs }:
    {
      nixosConfigurations = {
        bifrostix = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./modules/docker-lane.nix
            ./hosts/bifrostix.nix
          ];
        };
      };
    };
}

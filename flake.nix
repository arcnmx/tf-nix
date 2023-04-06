{
  description = "terraform meets nix";
  inputs = {
    nixpkgs = { };
    config = {
      url = "github:input-output-hk/empty-flake";
    };
  };
  outputs = { self, nixpkgs, config, ... }: let
    nixlib = nixpkgs.lib;
    forAllSystems = nixlib.genAttrs nixlib.systems.flakeExposed;
    config' = config.lib.tfConfig.path or config.outPath;
    wrapModules = modules: let
      named = builtins.removeAttrs modules [ "__functor" ];
    in builtins.mapAttrs (_: module: { ... }: { imports = [ module ]; }) named // {
      default = modules.__functor modules;
    };
  in {
    legacyPackages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      legacyPackages = self.legacyPackages.${system};
    in {
      eval = { config ? config' }: import ./. {
        inherit pkgs config;
      };
      config = nixlib.makeOverridable legacyPackages.eval { };
      example = nixlib.genAttrs self.lib.example.names (example: nixlib.makeOverridable legacyPackages.eval {
        config = ./example + "/${example}.nix";
      });
      run = legacyPackages.config.run;
      lib = import ./lib {
        inherit pkgs;
        lib = nixlib;
      };
    });
    nixosModules = wrapModules self.lib.modules.nixos;
    homeModules = wrapModules self.lib.modules.home;
    metaModules = wrapModules self.lib.modules.tf;
    lib = {
      modules = import ./modules;
      tf = import ./lib/lib.nix {
        lib = nixlib;
      };
      example.names = [ "digitalocean" ];
    };
  };
}

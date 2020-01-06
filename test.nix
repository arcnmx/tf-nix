{ pkgs ? import <nixpkgs> { }, config ? ./example/terranix.nix }: with pkgs.lib; let
  /*metaModule = { config, ... }: {
    options = {
      terraform = mkOption {
        type = types.submodule terraformModule;
        default = { };
      };
      terranix = {
        gcroots = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
        targets = mkOption {
          type = types.attrsOf (types.listOf types.str);
          default = { };
        };
      };
      nixos = mkOption {
        type = types.submodule ({ ... }: {
          imports = import (pkgs.path + "/nixos/modules/module-list.nix");
        });
        default = { };
      };
    };
    config = {
      nixos = {
        nixpkgs.system = pkgs.system;
        lib.terranix = {
          inherit terraformExpr terraformContext terraformReferences;
          terraformOutput = terraformOutput config;
          terraformProvider = terraformProvider config;
          terraformReference = terraformReference config;
          terraformConnectionDetails = terraformConnectionDetails config;
          terraformNixStoreUrl = terraformNixStoreUrl config;
          terraformSecret = terraformSecret config;
          terraformInput = terraformInput config;
          terraformJson = terraformJson config;
        };
        lib.dag = dag;
      };
      _module.args.pkgs = pkgs;
    };
  };*/
  config' = config;
  meta = { ... }: {
    config._module.args = {
      inherit pkgs;
    };
  };
  deps = { config, ... }: {
    options.dag = mkOption {
      type = types.submodule (import ./modules/deps.nix);
      default = { };
    };
    config.dag.terraformConfig = config;
  };
  depsType = { ... }: {
    imports = [
      ./modules/deps.nix
    ];
  };
  evalTerraform = config: (evalModules {
    modules = [
      meta
      deps
      config
      ./modules/terraform.nix
    ];
  }).config;
in rec {
  config = evalTerraform config';
  example = (evalModules {
    modules = [
      meta
      ./example/example.nix
    ];
    specialArgs = {
      modulesPath = pkgs.path + "/nixos/modules";
    };
  }).config;
}

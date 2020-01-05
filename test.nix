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
  evalTerraform = config: (evalModules {
    modules = [
      config
      ./modules/terraform.nix
      ./modules/deps.nix
    ];
  }).config;
in rec {
  config = evalTerraform config';
}

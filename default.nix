{ pkgs ? import <nixpkgs> { }, config ? ./example/example.nix }: with pkgs.lib; let
  pkgsModule = { ... }: {
    config._module.args = {
      pkgs = mkDefault pkgs;
    };
  };
  nixosModulesPath = toString (pkgs.path + "/nixos/modules");
  configPath = config;
  configModule = { pkgs, config, ... }: {
    options = {
      paths = {
        cwd = mkOption {
          type = types.path;
        };
        config = mkOption {
          type = types.path;
          default = configPath;
        };
        dataDir = mkOption {
          type = types.path;
          default = config.paths.cwd + "/terraform";
        };
        tf = mkOption {
          type = types.path;
          default = ./.;
        };
      };
      shell = mkOption {
        type = types.package;
      };
    };

    config = {
      deps = {
        enable = true;
      };
      runners.lazy = {
        file = ./.;
        args = [ "--show-trace" "--arg" "config" (toString config.paths.config) ];
      };
      state = {
        file = config.paths.dataDir + "/terraform.tfstate";
      };
      terraform = {
        dataDir = config.paths.dataDir + "/tfdata";
        logPath = config.paths.dataDir + "/terraform.log";
        #environment = {
        #  #TF_INPUT = "0";
        #};
      };
      paths = let
        pwd = builtins.getEnv "PWD";
      in {
        cwd = mkIf (pwd != "") (mkDefault pwd);
      };
      shell = shell' config;
    };
  };
  tfEval = config: (evalModules {
    modules = [
      pkgsModule
      configModule
      ./modules
    ] ++ toList config;

    specialArgs = {
      inherit nixosModulesPath;
      pkgsPath = toString pkgs.path;
      lib = pkgs.lib.extend (_: _: {
        inherit nixosModule nixosType;
      });
    };
  }).config;
  nixosModule = { config, ... }: {
    nixpkgs = {
      system = mkDefault pkgs.system;
    };

    _module.args.pkgs = mkDefault (import pkgs.path {
      inherit (config.nixpkgs) config overlays localSystem crossSystem;
    });
  };
  nixosType = modules: let
    baseModules = import (pkgs.path + "/nixos/modules/module-list.nix");
  in types.submoduleWith {
    modules = baseModules ++ [
      nixosModule
    ] ++ toList modules;

    specialArgs = {
      inherit baseModules;
      modulesPath = nixosModulesPath;
    };
  };
  shell' = config: let
    shell = pkgs.mkShell {
      nativeBuildInputs = with config.runners.run; [ terraform.package apply.package ];

      inherit (config.terraform.environment) TF_DATA_DIR;
      TF_DIR = toString config.paths.dataDir;

      shellHook = ''
        mkdir -p $TF_DATA_DIR
        HISTFILE=$TF_DIR/history
        unset SSH_AUTH_SOCK
      '';
    };
  in shell;
in tfEval config

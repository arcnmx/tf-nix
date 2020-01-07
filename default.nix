{ pkgs ? import <nixpkgs> { }, config ? ./example/example.nix, terraformState ? null, terraformTargets ? [] }: with pkgs.lib; let
  inherit (import ./modules/run.nix { inherit pkgs; }) nixRunWrapper;
  terraformSecret = config: name: let
  in throw "ugh secret ${name}";
  pkgsModule = { ... }: {
    config._module.args = {
      pkgs = mkDefault pkgs;
    };
  };
  nixosModulesPath = toString (pkgs.path + "/nixos/modules");
  tfModule = ./modules/terraform.nix;
  tfEvalDeps = { config }: let
    depsModule = { ... }: {
      config.terraformConfig = config;
    };
  in (evalModules {
    modules = [
      pkgsModule
      depsModule
      ./modules/deps.nix
    ];
  }).config;
  configPath = config;
  configModule = { config, ... }: {
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
        terraformDataDir = mkOption {
          type = types.path;
          default = config.paths.dataDir + "/tfdata";
        };
        stateFile = mkOption {
          type = types.path;
          default = config.paths.dataDir + "/tf.tfstate";
        };
        tf = mkOption {
          type = types.path;
          default = ./.;
        };
      };
    };

    config = {
      paths = let
        pwd = builtins.getEnv "PWD";
      in {
        cwd = mkIf (pwd != "") (mkDefault pwd);
      };
    };
  };
  tfEval = config: (evalModules {
    modules = [
      pkgsModule
      tfModule
      configModule
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
  terraform = {
    config
  , deps ? null
  }: let
    dir = config.lib.tf.hclDir {
      hcl = if deps == null then config.hcl else deps.hcl;
    };
    script = ''
      set -eu

      export TF_CONFIG_DIR="${dir}"

      exec ${config.terraform.package}/bin/terraform "$@"
    '';
  in pkgs.writeShellScriptBin "terraform" script;
  apply = {
    config
  , deps
  , targets ? optionals (!deps.isComplete) deps.targets
  }: let
    package = terraform {
      inherit config deps;
    };
    script = ''
      set -eux

      export TF_DATA_DIR="''${TF_DATA_DIR-${config.paths.terraformDataDir}}"
      export TF_STATE_FILE="''${TF_STATE_FILE-${config.paths.stateFile}}"
      export TF_TARGETS="${concatStringsSep " " targets}"

      ${package}/bin/terraform apply "$@"
    '' + optionalString (!deps.isComplete) ''
      nix run -f ${toString config.paths.tf} run.apply --arg config ${toString config.paths.config} --arg terraformState $TF_STATE_FILE --argstr terraformTargets "${concatStringsSep "," targets}"
    '';
  in pkgs.writeShellScriptBin "terraform" script;
  commonEnv = {
    TF_CLI_CONFIG_FILE = builtins.toFile "terraformrc" ''
      disable_checkpoint = true
    '';
    TF_INPUT = 0;
    TF_IN_AUTOMATION = 1;
    #TF_LOG = "INFO";
  };
  shell' = config: let
    TF_DIR = toString config.paths.dataDir;
    TF_STATE_FILE = toString config.paths.stateFile;
    TF_DATA_DIR = toString config.paths.terraformDataDir;
    shell = pkgs.mkShell (commonEnv // {
      inherit TF_STATE_FILE TF_DIR TF_DATA_DIR;
      TF_LOG_PATH = "${TF_DIR}/log.txt";
      # TODO: secret input commands here
      shellHook = ''
        mkdir -p $TF_DATA_DIR
        HISTFILE=$TF_DIR/history
        unset SSH_AUTH_SOCK
      '';
    });
  in shell;
  config' = tfEval config;
in rec {
  config = config';
  run = {
    apply = let
      pkg = apply {
        inherit config;
        deps = tfEvalDeps {
          inherit config;
        };
      };
    in nixRunWrapper "terraform" pkg;
    terraform = let
      pkg = terraform {
        inherit config;
        deps = tfEvalDeps {
          inherit config;
        };
      };
    in nixRunWrapper "terraform" pkg;
  };
  shell = shell' config;
}

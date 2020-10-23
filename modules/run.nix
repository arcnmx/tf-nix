{ config, pkgs, lib, ... }: with lib; let
  inherit (import ../lib/run.nix { inherit pkgs; }) nixRunWrapper;
  cfg = config.runners;
  runType = types.submodule ({ config, name, ... }: {
    options = {
      executable = mkOption {
        type = types.str;
        default = name;
      };
      command = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      package = mkOption {
        type = types.package;
      };
      runner = mkOption {
        type = types.package;
      };
    };
    config = {
      runner = mkOptionDefault (nixRunWrapper config.executable config.package);
      package = mkOptionDefault (pkgs.writeShellScriptBin config.executable config.command);
    };
  });
in {
  options = {
    runners = {
      run = mkOption {
        type = types.attrsOf runType;
        default = { };
      };
    };
    run = mkOption {
      type = types.attrsOf types.unspecified;
    };
  };

  config = {
    run = mapAttrs (_: r: r.runner) cfg.run;
  };
}

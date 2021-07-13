{ options, config, pkgs, lib, ... }: with lib; let
  cfg = config.lazy;
  opts = options.lazy;
  inherit (lib.tf) syntax;
  lazyValueType = types.submodule ({ options, config, name, ... }: {
    options = {
      name = mkOption {
        type = types.str;
        default = name;
      };
      file = mkOption {
        type = types.path;
      };
      args = {
        cli = mkOption {
          type = with types; listOf str;
          default = [ ];
          example = [ "--show-trace" ];
        };
        nix = mkOption {
          type = with types; attrsOf syntax.argValueType;
          default = { };
        };
        conf = mkOption {
          type = with types; attrsOf syntax.optionValueType;
          default = { };
        };
      };
      attr = mkOption {
        type = attrType;
      };
      value = mkOption {
        type = types.unspecified;
      };
      set = mkOption {
        type = types.unspecified;
        readOnly = true;
      };
      out = {
        eval = mkOption {
        };
        attr = mkOption {
          type = types.listOf types.str;
          readOnly = true;
        };
      };
    };
    config = {
      file = mkIf opts.defaults.file.isDefined (mkOptionDefault cfg.defaults.file);
      value = mkIf options.attr.isDefined (mkOptionDefault (attrByPath config.attr config));
      args = {
        cli = cfg.args.cli ++ syntax.cliArgs {
          nixVersion = if cfg.package != null
            then cfg.package.version
            else builtins.nixVersion;
          inherit (config) file;
          inherit (config.out) attr;
          args = config.args.nix;
          options = config.args.conf;
        };
        nix = mapAttrs (_: mkOptionDefault) cfg.args.nix;
        conf = mapAttrs (_: mkOptionDefault) cfg.args.conf;
      };
      out = {
        attr = cfg.attrPrefix ++ singleton name;
      };
      set = {
        inherit (config) attr file executable name;
      };
    };
  });
in {
  options = {
    lazy = {
      package = mkOption {
        type = types.nullOr types.package;
        default = null;
        example = "pkgs.nix";
      };
      nixPrefix = mkOption {
        type = types.str;
        default = if cfg.package != null
          then "${cfg.package}/bin/"
          else "";
        readOnly = true;
      };
      /*nixRun = mkOption {
        type = types.listOf types.str;
        default = [ "${cfg.nixPrefix}nix" "run" ];
      };*/
      defaults = {
        file = mkOption {
          type = types.path;
        };
        args.nix = mkOptions {
          type = types.attrsOf argValueType;
          default = { };
        };
        configuration = mkOptions {
          type = types.attrsOf optionValueType;
          default = { };
        };
      };
      attrPrefix = mkOption {
        type = attrType;
        default = [ ];
        example = [ "config" ];
      };
      values = mkOption {
        type = types.attrsOf lazyValueType;
      };
    };
  };

  config = {
    lazy = {
      run = mapAttrs' (k: run: nameValuePair k (mapAttrs (_: mkDefault) {
        attr = "${cfg.lazy.attrPrefix}${k}.package";
        inherit (cfg.lazy) file;
        inherit (run) executable name;
      } // {
        inherit (cfg.lazy) args;
      })) cfg.run;
      nativeBuildInputs = mapAttrsToList (k: v: pkgs.writeShellScriptBin v.name ''
        exec ${escapeShellArgs v.out.runArgs} "$@"
      '') cfg.lazy.run;
    };
    run = mapAttrs (_: r: r.runner) cfg.run;
  };
}

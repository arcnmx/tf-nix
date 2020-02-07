isNixos: { pkgs, config, lib, ... }: with lib; let
  cfg = config.secrets;
  defaultOwner = if isNixos then "root" else config.home.username;
  defaultGroup = if isNixos then "keys" else "users";
  activationScript = "${pkgs.coreutils}/bin/install -dm 0755 ${cfg.persistentRoot}"
  + concatStringsSep "\n" (mapAttrsToList (_: f: let
      inherit (f.out) dir;
      dirModeStr = "-m7755"
        + optionalString (f.owner != cfg.owner) " -o${f.owner}"
        + optionalString (f.group != cfg.group) " -g${f.group}";
      modeStr = "-m${f.mode}"
        + optionalString (f.owner != cfg.owner) " -o${f.owner}"
        + optionalString (f.group != cfg.group) " -g${f.group}";
      source = if f.text != null
        then builtins.toFile f.fileName f.text
        else f.source;
    in "${pkgs.coreutils}/bin/install ${dirModeStr} -d ${dir}" +
      optionalString (!f.external) "\n${pkgs.coreutils}/bin/install -m${f.mode} ${source} ${f.path}"
    ) config.secrets.files);
  fileType = types.submodule ({ name, config, ... }: {
    options = {
      text = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      source = mkOption {
        type = types.nullOr types.path;
        default = null;
      };
      sha256 = mkOption {
        type = types.str;
      };
      persistent = mkOption {
        type = types.bool;
        default = cfg.persistent;
      };
      external = mkOption {
        type = types.bool;
        default = cfg.external;
      };
      owner = mkOption {
        type = types.str;
        default = cfg.owner;
      };
      group = mkOption {
        type = types.str;
        default = cfg.group;
      };
      mode = mkOption {
        type = types.str;
        default = "0400";
      };
      fileName = mkOption {
        type = types.str;
        default = name;
      };

      path = mkOption {
        type = types.path;
        internal = true;
      };
      out = {
        dir = mkOption {
          type = types.path;
          internal = true;
        };
        checkHash = mkOption {
          type = types.bool;
          internal = true;
        };
      };
    };

    config = let
      textHash = builtins.hashString "sha256" config.text;
      fileHash = builtins.hashFile "sha256" config.source;
    in {
      sha256 = mkMerge [
        (mkIf (config.text != null)
          (mkDefault textHash))
        (mkIf (config.text == null && builtins ? hashFile)
          (mkDefault fileHash))
      ];
      path = mkOptionDefault "${config.out.dir}/${config.fileName}";
      out = {
        dir = let
          root = if config.persistent then cfg.persistentRoot else cfg.root;
        in mkOptionDefault "${root}/${config.sha256}";
        checkHash = # TODO: add this to assertions
          if builtins.pathExists config.source then config.sha256 == fileHash
          else if config.text != null then config.sha256 == textHash
          else true; # TODO: null instead?
      };
    };
  });
in {
  options.secrets = {
    enable = mkOption {
      type = types.bool;
      default = cfg.files != { };
    };
    owner = mkOption {
      type = types.str;
      default = if isNixos then "root" else config.home.username;
    };
    group = mkOption {
      type = types.nullOr types.str;
      default = if isNixos then "keys" else "users";
    };
    files = mkOption {
      type = types.loaOf fileType;
      default = { };
    };
    root = mkOption {
      type = types.path;
      default = if isNixos
        then "/var/run/arc/secrets"
        else "${config.xdg.runtimeDir}/arc/secrets"; # TODO: use a /tmp dir or other tmpfs instead?
    };
    persistentRoot = mkOption {
      type = types.path;
      default = if isNixos
        then "/var/lib/arc/secrets"
        else "${config.xdg.cacheHome}/arc/secrets";
    };
    persistent = mkOption {
      type = types.bool;
      default = true;
    };
    external = mkOption {
      type = types.bool;
      default = false;
    };
  };

  config = mkIf cfg.enable (if isNixos then {
    system.activationScripts.arc_secrets = {
      text = activationScript;
      deps = [ "etc" ]; # must be done after passwd/etc are ready
    };

    users.groups.${cfg.group}.members = [ ];
  } else {
    home.activation.arc_secrets = config.lib.dag.entryAfter ["writeBoundary"] activationScript;
  });
}

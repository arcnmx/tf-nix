isNixos: { pkgs, config, lib, ... }: with lib; let
  cfg = config.secrets;
  activationScript = concatStringsSep "\n" (concatLists (mapAttrsToList (_: f: let
    source = if f.source != null
      then f.source
      else builtins.toFile f.fileName f.text;
    external = ''
      if [[ ! -e ${toString f.path} ]]; then
        echo "WARN: secret at ${toString f.path} does not exist" >&2
      else
        ${pkgs.coreutils}/bin/chown ${f.owner}:${f.group} ${toString f.path}
      fi
    '';
    embedded = ''
      ${pkgs.coreutils}/bin/install -m${f.mode} -o ${f.owner} -g ${f.group} ${source} ${toString f.path}
    '';
  in [
    "${pkgs.coreutils}/bin/install -dm0755 -o ${f.out.rootOwner} -g ${f.out.rootGroup} ${toString f.out.root}"
    "${pkgs.coreutils}/bin/install -dm7755 -o ${f.out.rootOwner} -g ${f.out.rootGroup} ${toString f.out.dir}"
    (if f.external then external else embedded)
  ]) config.secrets.files));
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
        root = mkOption {
          type = types.path;
          internal = true;
        };
        rootOwner = mkOption {
          type = types.str;
          internal = true;
        };
        rootGroup = mkOption {
          type = types.str;
          internal = true;
        };
        dir = mkOption {
          type = types.path;
          internal = true;
        };
        checkHash = mkOption {
          type = types.bool;
          internal = true;
        };
        set = mkOption {
          type = types.unspecified;
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
      path = mkOptionDefault (toString (config.out.dir + "/${config.fileName}"));
      out = {
        root = mkOptionDefault (if config.persistent then cfg.persistentRoot else cfg.root);
        rootOwner = mkOptionDefault cfg.owner;
        rootGroup = mkOptionDefault cfg.group;
        dir = mkOptionDefault (config.out.root + "/${builtins.unsafeDiscardStringContext config.sha256}");
        checkHash = # TODO: add this to assertions
          if config.source != null && builtins.pathExists config.source then config.sha256 == fileHash
          else if config.text != null then config.sha256 == textHash
          else true; # TODO: null instead?
        set = {
          inherit (config) text source sha256 persistent external owner group mode fileName path;
          out = {
            inherit (config.out) root dir rootOwner rootGroup;
          };
        };
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
        then /var/run/arc/secrets
        else /dev/shm + "/arc-${config.home.username}/secrets";
    };
    persistentRoot = mkOption {
      type = types.path;
      default = if isNixos
        then /var/lib/arc/secrets
        else config.xdg.cacheHome + "/arc/secrets";
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

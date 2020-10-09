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
      chown =
        optionalString (f.owner != cfg.owner) "${f.owner}"
        + optionalString (f.group != cfg.group) ":${f.group}";
      source = if f.text != null
        then builtins.toFile f.fileName f.text
        else f.source;
    in "${pkgs.coreutils}/bin/install ${dirModeStr} -d ${dir}" +
      optionalString (!f.external) "\n${pkgs.coreutils}/bin/install -m${f.mode} ${source} ${f.path}" +
      optionalString (f.external && chown != "") "\n${pkgs.coreutils}/bin/chown ${chown} ${f.path}"
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
        set = mkOption {
          type = types.unspecified;
          internal = true;
        };
        tf = {
          key = mkOption {
            type = types.str;
            internal = true;
          };
          setResource = mkOption {
            type = types.unspecified;
            internal = true;
          };
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
        in mkOptionDefault "${root}/${builtins.unsafeDiscardStringContext config.sha256}";
        checkHash = # TODO: add this to assertions
          if builtins.pathExists config.source then config.sha256 == fileHash
          else if config.text != null then config.sha256 == textHash
          else true; # TODO: null instead?
        tf = {
          setResource = {
            #inherit filename user mode connection content;
            provider = "null";
            type = "resource";
            inherit (cfg.tf) connection;
            inputs.triggers = {
              inherit (config) sha256 text owner group mode;
              # TODO: terraform hash text expr?
              source = toString config.source;
              path = toString config.path;
            } // cfg.tf.triggers;
            provisioners = [ {
              type = "remote-exec";
              remote-exec.inline = [
                "mkdir -p ${builtins.dirOf config.path}"
              ];
            } {
              type = "file";
              file = {
                content = mkIf (config.text != null) config.text;
                source = mkIf (config.source != null) (toString config.source);
                destination = config.path;
              };
            } {
              type = "remote-exec";
              remote-exec.inline = [
                "chown ${config.owner}:${config.group} ${config.path}" # NOTE: user/group might not exist yet :<
                "chmod ${config.mode} ${config.path}"
              ];
            } ];
          };
          key = "secret-${cfg.tf.keyPrefix}${replaceStrings [ "." ] [ "_" ] config.fileName}";
        };
        set = {
          inherit (config) text source sha256 persistent external owner group mode fileName path;
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
    tf = {
      connection = mkOption {
        type = types.unspecified;
      };
      keyPrefix = mkOption {
        type = types.str;
      };
      triggers = mkOption {
        type = types.attrsOf types.str;
        default = {
          inherit (cfg.tf.connection) host;
        };
      };
    };
  };

  config = mkIf cfg.enable (if isNixos then {
    secrets.tf.keyPrefix = mkOptionDefault "${config.networking.hostName}-";
    system.activationScripts.arc_secrets = {
      text = activationScript;
      deps = [ "etc" ]; # must be done after passwd/etc are ready
    };

    users.groups.${cfg.group}.members = [ ];
  } else {
    home.activation.arc_secrets = config.lib.dag.entryAfter ["writeBoundary"] activationScript;
  });
}

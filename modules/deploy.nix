{ pkgs, config, lib, ... }: with lib; let
  tf = config;
  cfg = config.deploy;
  interpreter = mkIf (!cfg.isRoot) [ "sudo" "bash" "-c" ];
  deploySubmodule = { name, config, ... }: {
    options = {
      enable = mkEnableOption "deploy" // {
        default = true;
      };
      nixosConfig = mkOption {
        type = types.nullOr types.unspecified;
        default = null;
      };
      name = mkOption {
        type = types.str;
        default = name;
      };
      system = mkOption {
        type = types.package;
        default = config.nixosConfig.system.build.toplevel;
      };
      isRemote = mkOption {
        type = types.bool;
        default = true;
      };
      connection = mkOption {
        type = tf.lib.tf.tfTypes.connectionType null;
      };
      gcroot = {
        enable = mkEnableOption "gcroot" // {
          default = cfg.gcroot.enable;
        };
        name = mkOption {
          type = types.str;
          default = config.name;
        };
        path = mkOption {
          type = types.path;
          default = let
            root = if cfg.gcroot.useProfiles then cfg.gcroot.profilePath else cfg.gcroot.gcrootPath;
          in "${root}-${config.gcroot.name}";
        };
      };
      secrets = {
        files = mkOption {
          type = types.attrsOf types.unspecified;
          default = [ ];
        };
        refIds = mkOption {
          type = types.separatedString "";
          default = "";
        };
        cacheDir = mkOption {
          type = types.path;
          default = cfg.secrets.cacheDir;
        };
      };
      triggers = {
        common = mkOption {
          type = types.attrsOf types.str;
          default = { };
        };
        copy = mkOption {
          type = types.attrsOf types.str;
          default = { };
        };
        secrets = mkOption {
          type = types.attrsOf types.str;
          default = { };
        };
        switch = mkOption {
          type = types.attrsOf types.str;
          default = { };
        };
        gcroot = mkOption {
          type = types.attrsOf types.str;
          default = { };
        };
      };
      out = {
        resourceName = mkOption {
          type = types.str;
          default = "${config.name}_system";
        };
        resource = {
          copy = mkOption {
            type = types.unspecified;
            default = tf.resources."${config.out.resourceName}_copy";
          };
          switch = mkOption {
            type = types.unspecified;
            default = tf.resources."${confg.out.resourceName}_switch";
          };
        };
        setResources = mkOption {
          type = types.attrsOf types.unspecified;
          default = { };
        };
      };
    };
    config = mkIf config.enable {
      secrets = {
        files = mkIf (config.nixosConfig ? secrets.files) (mkDefault config.nixosConfig.secrets.files);
        refIds = mkMerge (mapAttrsToList (key: _: tf.resources."${config.name}_${tf.lib.tf.terraformIdent key}".refAttr "id") config.secrets.files);
      };
      triggers = {
        copy = mapAttrs (_: mkOptionDefault) config.triggers.common // {
          system = "${config.system}";
        };
        switch = {
          copy = config.out.resource.copy.refAttr "id";
          secrets = config.secrets.refIds;
        };
        secrets = mapAttrs (_: mkOptionDefault) config.triggers.common;
        gcroot = {
          system = mkOptionDefault "${config.system}";
        };
      };
      out.setResources =
        listToAttrs (concatLists (mapAttrsToList (key: file: let
          name = "${config.name}_${tf.lib.tf.terraformIdent key}";
          source = if file.source != null then toString file.source else tf.resources."${name}_file".refAttr "filename";
        in singleton (nameValuePair name {
          provider = "null";
          type = "resource";
          connection = mkIf config.isRemote config.connection.set;
          inputs.triggers = {
            inherit (file) sha256 owner group mode;
            path = toString file.path;
          } // optionalAttrs (file.source == null) {
            file = tf.resources."${name}_file".refAttr "id";
          } // optionalAttrs (file.source != null) {
            inherit source;
          } // config.triggers.secrets;
          provisioners = if config.isRemote then [ {
            type = "remote-exec";
            remote-exec.inline = [
              "install -dm0755 -o ${file.out.rootOwner} -g ${file.out.rootGroup} ${toString file.out.root}"
              "install -dm7755 -o ${file.out.rootOwner} -g ${file.out.rootGroup} ${toString file.out.dir}"
            ];
          } {
            type = "file";
            file = {
              inherit source;
              destination = toString file.path;
            };
          } {
            type = "remote-exec";
            remote-exec.inline = [
              "chown ${file.out.rootOwner}:${file.out.rootGroup} ${toString file.path}"
              "chown ${file.owner}:${file.group} ${toString file.path}"
              "chmod ${file.mode} ${toString file.path}"
            ];
          } ] else [ {
            type = "local-exec";
            local-exec = {
              inherit interpreter;
              command = concatStringsSep " && " [
                "install -dm0755 -o ${file.out.rootOwner} -g ${file.out.rootGroup} ${toString file.out.root}"
                "install -dm7755 -o ${file.out.rootOwner} -g ${file.out.rootGroup} ${toString file.out.dir}"
                "install -o ${file.out.rootOwner} -g ${file.out.rootGroup} -m ${file.mode} ${source} ${toString file.path}"
              ];
            };
          } {
            type = "local-exec";
            local-exec = {
              inherit interpreter;
              command = concatStringsSep "; " [
                "chown ${file.owner}:${file.group} ${toString file.path}"
                "true"
              ];
            };
          } ];
        }) ++ optional (file.source == null) (nameValuePair "${name}_file" {
          provider = "local";
          type = "file";
          inputs = {
            filename = "${toString config.secrets.cacheDir}/${name}.secret";
            sensitive_content = file.text;
            file_permission = "0600";
          };
        })) config.secrets.files)) // {
        "${config.out.resourceName}_copy" = {
          provider = "null";
          type = "resource";
          connection = mkIf config.isRemote config.connection.set;
          inputs.triggers = config.triggers.copy;
          provisioners = mkIf config.isRemote [ {
            # wait for remote host to come online
            type = "remote-exec";
            remote-exec.inline = [ "true" ];
          } {
            type = "local-exec";
            local-exec = {
              environment.NIX_SSHOPTS = config.connection.out.ssh.nixStoreOpts;
              command = "nix copy --substitute-on-destination --to ${config.connection.nixStoreUrl} ${config.system}";
            };
          } ];
        };
        "${config.out.resourceName}_switch" = {
          provider = "null";
          type = "resource";
          connection = mkIf config.isRemote config.connection.set;
          inputs.triggers = config.triggers.switch;
          provisioners = let
            commands = [
              "nix-env -p /nix/var/nix/profiles/system --set ${config.system}"
              "${config.system}/bin/switch-to-configuration switch"
            ];
            remote = {
              type = "remote-exec";
              remote-exec.inline = commands;
            };
            local = {
              type = "local-exec";
              local-exec = {
                inherit interpreter;
                command = concatStringsSep " && " commands;
              };
            };
          in if config.isRemote then [ remote ] else [ local ];
        };
        "${config.out.resourceName}_gcroot" = {
          enable = config.gcroot.enable && config.isRemote;
          provider = "null";
          type = "resource";
          inputs.triggers = config.triggers.gcroot;
          provisioners = let
            indirectGcroot = tf.terraform.dataDir != null;
            gcrootTarget = if indirectGcroot
              then tf.terraform.dataDir + "/gcroot-${config.gcroot.name}"
              else config.gcroot.path;
            setProfile = [
              ''nix-env -p "${config.gcroot.path}" --set ${config.system}''
            ] ++ optional indirectGcroot ''ln -sfn "${config.gcroot.path}" "${toString gcrootTarget}"'';
            setGcroot = [
              ''ln -sfn ${config.system} "${toString gcrootTarget}"''
            ] ++ optional indirectGcroot ''ln -sfn "${toString gcrootTarget}" "${config.gcroot.path}"'';
            commands = if cfg.gcroot.useProfiles then setProfile else setGcroot;
          in singleton {
            local-exec.command = concatStringsSep " && " commands;
          };
        };
      };
    };
  };
in {
  options.deploy = {
    systems = mkOption {
      type = types.attrsOf (types.submodule deploySubmodule);
      default = { };
    };
    isRoot = mkOption {
      type = types.bool;
      default = false;
    };
    secrets = {
      cacheDir = mkOption {
        type = types.path;
        default = tf.terraform.dataDir + "/secrets";
      };
    };
    gcroot = {
      enable = mkEnableOption "gcroots by default";
      useProfiles = mkOption {
        type = types.bool;
        default = false;
      };
      user = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      name = mkOption {
        type = types.str;
        default = "tf";
      };
      profilePath = mkOption {
        type = types.path;
        default = "/nix/var/nix/profiles"
        + optionalString (cfg.gcroot.user != null) "/per-user/${cfg.gcroot.user}"
        + "/${cfg.gcroot.name}";
      };
      gcrootPath = mkOption {
        type = types.path;
        default = "/nix/var/nix/gcroots"
        + optionalString (cfg.gcroot.user != null) "/per-user/${cfg.gcroot.user}"
        + "/${cfg.gcroot.name}";
      };
    };
  };

  config = {
    resources = mkMerge (mapAttrsToList (_: system: system.out.setResources) cfg.systems);
    outputs = mkMerge (mapAttrsToList (_: system: mkIf system.enable {
      "${system.out.resourceName}_ssh" = {
        value = {
          inherit (system.connection.out.ssh) destination cliArgs opts;
          inherit (system.connection) nixStoreUrl host port;
        };
        sensitive = true;
      };
    }) cfg.systems);
    runners.run = mkMerge (mapAttrsToList (_: system: mkIf system.enable {
      "${system.name}-ssh" = {
        command = let
          ssh = tf.outputs."${system.out.resourceName}_ssh".import;
        in ''
          exec ${pkgs.openssh}/bin/ssh ${escapeShellArgs ssh.cliArgs} ${escapeShellArg ssh.destination} "$@"
        '';
      };
    }) cfg.systems);
  };
}

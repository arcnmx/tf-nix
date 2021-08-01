{ pkgs, config, lib, ... }: with lib; let
  tf = config;
  cfg = config.deploy.lustrate;
  lustrateSubmodule = { config, ... }: {
    options = {
      lustrate = {
        enable = mkEnableOption "NIXOS_LUSTRATE";

        connection = mkOption {
          type = tf.lib.tf.tfTypes.connectionType null;
          default = config.connection.set;
        };

        install = mkOption {
          type = types.bool;
          default = true;
          description = "Install Nix";
        };

        whitelist = mkOption {
          type = with types; listOf path;
        };
        mount = mkOption {
          type = with types; listOf str;
        };
        unmount = mkOption {
          type = with types; listOf path;
        };

        scripts = {
          install = mkOption {
            type = types.lines;
          };
          mount = mkOption {
            type = types.lines;
          };
          prepare = mkOption {
            type = types.lines;
          };
          lustrate = mkOption {
            type = types.lines;
          };
        };
      };
      triggers = {
        lustrate_install = mkOption {
          type = types.attrsOf types.str;
          default = { };
        };
        lustrate_copy = mkOption {
          type = types.attrsOf types.str;
          default = { };
        };
        lustrate = mkOption {
          type = types.attrsOf types.str;
          default = { };
        };
      };
      out.resource = {
        lustrate_install = mkOption {
          type = types.unspecified;
          default = tf.resources."${config.out.resourceName}_lustrate_install";
        };
        lustrate_copy = mkOption {
          type = types.unspecified;
          default = tf.resources."${config.out.resourceName}_lustrate_copy";
        };
        lustrate = mkOption {
          type = types.unspecified;
          default = tf.resources."${config.out.resourceName}_lustrate";
        };
      };
    };
    config = {
      lustrate = {
        whitelist = [
          "/root/.ssh/authorized_keys"
        ];
        unmount = [
          "/boot"
        ];
        mount = mkIf (config.nixosConfig.fileSystems ? "/boot") [
          "/boot"
        ];
        scripts = {
          install = ''
            #!/usr/bin/env bash
            set -eu

            if command -v nix > /dev/null; then
              # skip install if nix already exists
              exit 0
            fi

            groupadd nixbld -g 30000 || true
            for i in {1..10}; do
              useradd -c "Nix build user $i" -d /var/empty -g nixbld -G nixbld -M -N -r -s "$(command -v nologin)" "nixbld$i" || true
            done

            curl -L https://nixos.org/nix/install | $SHELL
            sed -i -e '1s_^_source ~/.nix-profile/etc/profile.d/nix.sh\n_' ~/.bashrc # must be at beginning of file
          ''; # TODO: tmp mkswap and swapon because nix copy can eat rams thanks
          mount = ''
            #!/usr/bin/env bash
            set -eu

            if [[ -e /etc/NIXOS ]]; then
              exit 0
            fi

            find /boot -type f -delete
            umount -Rq ${escapeShellArgs config.lustrate.unmount} || true
          '' + concatMapStringsSep "\n" (mount: "mount ${escapeShellArgs [ config.nixosConfig.fileSystems.${mount}.device mount ]}") config.lustrate.mount;
          prepare = ''
            #!/usr/bin/env bash
            set -eu

            if [[ -e /etc/NIXOS ]]; then
              exit 0
            fi

            touch /etc/NIXOS
            touch /etc/NIXOS_LUSTRATE
            printf '%s\n' ${escapeShellArgs config.lustrate.whitelist} >> /etc/NIXOS_LUSTRATE

            nix-env -p /nix/var/nix/profiles/system --set ${config.system}
            /nix/var/nix/profiles/system/bin/switch-to-configuration boot
          '';
          lustrate = ''
            #!/usr/bin/env bash
            set -eu

            if [[ -e /etc/NIXOS_LUSTRATE ]]; then
              reboot
            fi
          '';
        };
      };
      triggers = mkIf config.lustrate.enable {
        lustrate_install = mapAttrs (_: mkOptionDefault) config.triggers.common // {
          install_enable = toString config.lustrate.install;
        };
        lustrate_copy = {
          install = config.out.resource.lustrate_install.refAttr "id";
        };
        lustrate = {
          copy = config.out.resource.lustrate_copy.refAttr "id";
        };
        copy = {
          lustrate = config.out.resource.lustrate.refAttr "id";
        };
        secrets = {
          lustrate = config.out.resource.lustrate.refAttr "id";
        };
      };
      out.setResources = mkIf config.lustrate.enable {
        "${config.out.resourceName}_lustrate_install" = {
          provider = "null";
          type = "resource";
          connection = config.lustrate.connection.set;
          inputs.triggers = config.triggers.lustrate_install;
          provisioners = mkIf config.lustrate.install [
            { file = {
              destination = "/tmp/lustrate-install";
              content = config.lustrate.scripts.install;
            }; }
            { remote-exec.command = "bash -x /tmp/lustrate-install"; }
          ];
        };
        "${config.out.resourceName}_lustrate_copy" = {
          provider = "null";
          type = "resource";
          connection = config.lustrate.connection.set;
          inputs.triggers = config.triggers.lustrate_copy;
          provisioners = [
            { # wait for remote host to come online
              type = "remote-exec";
              remote-exec.inline = [ "true" ];
            }
            { local-exec = {
              environment.NIX_SSHOPTS = config.lustrate.connection.out.ssh.nixStoreOpts;
              command = "nix copy --substitute-on-destination --to ${config.lustrate.connection.nixStoreUrl} ${config.system}";
            }; }
          ];
        };
        "${config.out.resourceName}_lustrate" = {
          provider = "null";
          type = "resource";
          connection = config.lustrate.connection.set;
          inputs.triggers = config.triggers.lustrate;
          provisioners = [
            { file = {
              destination = "/tmp/lustrate-mount";
              content = config.lustrate.scripts.mount;
            }; }
            { file = {
              destination = "/tmp/lustrate-prepare";
              content = config.lustrate.scripts.prepare;
            }; }
            { file = {
              destination = "/tmp/lustrate";
              content = config.lustrate.scripts.lustrate;
            }; }
            { remote-exec.command = "bash -x /tmp/lustrate-mount"; }
            { remote-exec.command = "bash -x /tmp/lustrate-prepare"; }
            { remote-exec.command = "bash -x /tmp/lustrate"; # reboot into new system
              onFailure = "continue";
            }
          ];
        };
      };
    };
  };
in {
  options.deploy = {
    systems = mkOption {
      type = types.attrsOf (types.submodule lustrateSubmodule);
    };
  };
}

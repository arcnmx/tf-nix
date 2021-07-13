{ lib, config, ... }: with lib; let
  inherit (config.lib.tf) terraformSelf;
  compartment_id = var.oci_compartment.ref;
  res = config.resources;
  var = config.variables;
  out = config.outputs;
  shape = "VM.Standard.E2.1.Micro";
  freeform_tags = {
    tfnix = true;
  };
  infectEnv = {
    NIXOS_IMPORT = "/tmp/infect.nix";
    NIX_CHANNEL = "nixos-21.05";
  };
  infectEnvStrs = mapAttrsToList (k: v: "${k}=${v}") infectEnv;
in {
  imports = [
    # common example system
    ./example.nix
    ./oracle-defaults.nix
  ];

  config = {
    resources = {
      namespace = {
        provider = "oci";
        type = "objectstorage_namespace";
        dataSource = true;
        inputs = {
          inherit compartment_id;
        };
      };

      nixos_image_object = mkIf (!config.nixosInfect) {
        provider = "oci";
        type = "objectstorage_object";
        lifecycle.ignoreChanges = [
          "source" # upload only once, subsequent changes are applied to instances on deploy
        ];
        inputs = {
          bucket = var.oci_bucket.ref;
          namespace = res.namespace.refAttr "namespace";
          object = "tfnix/example.qcow2";
          source = "${config.baseImage.system.build.ociImage}/nixos.qcow2";
        };
      };

      nixos_image = mkIf (!config.nixosInfect) {
        provider = "oci";
        type = "core_image";
        inputs = {
          inherit compartment_id freeform_tags;
          display_name = "nixos-tfnix-example";
          image_source_details = {
            source_image_type = "QCOW2";
            operating_system = "NixOS";
            operating_system_version = lib.version;
            #source_type = "objectStorageUri";
            #source_uri = nixos_image_object.refAttr "id"; # TODO: this isn't a full uri
            source_type = "objectStorageTuple";
            bucket_name = res.nixos_image_object.refAttr "bucket";
            namespace_name = res.nixos_image_object.refAttr "namespace";
            object_name = res.nixos_image_object.refAttr "object";
          };
          #launch_mode = "PARAVIRTUALIZED"; # "NATIVE" is better or worse? .-.
          launch_mode = "NATIVE"; # sounds better idk not clear to me
          #size_in_mbs # boot volume size
        };
      };

      generic_image = mkIf config.nixosInfect {
        provider = "oci";
        type = "core_images";
        dataSource = true;
        inputs = {
          inherit compartment_id shape;
          operating_system = "Canonical Ubuntu";
          #operating_system = "Oracle Linux";
          sort_by = "TIMECREATED";
          sort_order = "DESC";
        };
      };

      subnet = {
        provider = "oci";
        type = "core_subnets";
        dataSource = true;
        inputs = {
          inherit compartment_id;
        };
      };

      cloudinit = mkIf config.nixosInfect {
        provider = "cloudinit";
        type = "config";
        dataSource = true;
        inputs = {
          part = [
            /*{
              content_type = "text/cloud-config";
              content = "#cloud-config\n" + builtins.toJSON {
                disable_root = false;
                # we have provisioners for write_files so whatever
                write_files = [
                  {
                    path = "/infect.nix";
                    permissions = "0755";
                    content = ''
                      #!/usr/bin/env bash
                      set -eu

                      curl -L https://nixos.org/nix/install | $SHELL
                    '';
                  }
                ];
              };
            }*/
            /*{
              content_type = "text/x-shellscript";
              filename = "99-infect.sh";
              content = ''
                #!/usr/bin/env bash

                if [[ ! -e /etc/nixos/configuration.nix ]]; then
                  systemctl --no-block stop ssh

                  curl https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect |
                    env ${escapeShellArgs infectEnvStrs} bash -s 2>&1 | tee /var/log/infect.log
                  RES=$?

                  # this shouldn't return if it works...
                  if [[ $RES -ne 0 ]]; then
                    systemctl --no-block start ssh
                  fi

                  exit $RES
                fi
              '';
            }*/
          ];
        };
      };

      server = {
        provider = "oci";
        type = "core_instance";
        #lifecycle.ignoreChanges = [
        #  "metadata.ssh_authorized_keys" # docs say it can't change
        #  "metadata.user_data" # docs say it can't change
        #];
        connection = {
          host = terraformSelf "public_ip";
          ssh = {
            privateKey = res.access_key.refAttr "private_key_pem";
            privateKeyFile = res.access_file.refAttr "filename";
          };
        };
        inputs = {
          inherit compartment_id shape freeform_tags;
          availability_domain = res.availability_domain.refAttr "name";
          display_name = "tfnix-example";
          create_vnic_details = [
            {
              assign_public_ip = true;
              hostname_label = "tfnix-example";
              inherit freeform_tags;
              subnet_id = if res.subnet.dataSource
                then res.subnet.refAttr "subnets[0].id"
                else res.subnet.refAttr "id";
              nsg_ids = [ ];
            }
          ];
          extended_metadata = { };
          metadata = {
            ssh_authorized_keys = res.access_key.refAttr "public_key_openssh";
          } // optionalAttrs config.nixosInfect {
            user_data = res.cloudinit.refAttr "rendered";
          };
          source_details = {
            source_type = "image";
            source_id = if !config.nixosInfect
              then res.nixos_image.refAttr "id"
              else res.generic_image.refAttr "images[0].id";
            boot_volume_size_in_gbs = 50; # why is the minimum so high wtf..?
          };
        };
        provisioners = let
          system = config.baseImage.system.build.toplevel;
        in mkIf config.nixosInfect [
          { file = {
            destination = "/infect.nix";
            content = ''
              #!/usr/bin/env bash
              set -eu

              mount
              find /dev/disk

              groupadd nixbld -g 30000 || true
              for i in {1..10}; do
                useradd -c "Nix build user $i" -d /var/empty -g nixbld -G nixbld -M -N -r -s "$(command -v nologin)" "nixbld$i" || true
              done

              curl -L https://nixos.org/nix/install | $SHELL
              sed -i -e '1s_^_source ~/.nix-profile/etc/profile.d/nix.sh\n_' ~/.bashrc # must be at beginning of file
            ''; # TODO: tmp mkswap and swapon because nix copy can eat rams thanks
          }; }
          { file = {
            destination = "/infect.lustrate";
            content = ''
              #!/usr/bin/env bash
              set -eu

              touch /etc/NIXOS
              touch /etc/NIXOS_LUSTRATE
              echo /root/.ssh/authorized_keys >> /etc/NIXOS_LUSTRATE
            '';
          }; }
          { file = {
            destination = "/infect.switch";
            content = ''
              #!/usr/bin/env bash
              set -eu

              find /boot -type f -delete
              umount /boot/efi && mount ${config.nixos.fileSystems."/boot".device} /boot
              mount --move /boot/esp /boot || echo failed to move /boot/esp

              source ~/.nix-profile/etc/profile.d/nix.sh
              nix-env -p /nix/var/nix/profiles/system --set ${system}
              /nix/var/nix/profiles/system/bin/switch-to-configuration boot
            '';
          }; }
          { remote-exec.command = "bash -x /infect.nix"; }
          { remote-exec.command = "bash -x /infect.lustrate"; }
          { local-exec = {
            environment.NIX_SSHOPTS = res.server.connection.out.ssh.nixStoreOpts;
            command = "nix copy --substitute-on-destination --to ${res.server.connection.nixStoreUrl} ${system}";
          }; }
          { remote-exec.command = "bash -x /infect.switch"; }
          { remote-exec.command = "reboot";
            onFailure = "continue";
          }
        ];
      };

      availability_domain = {
        provider = "oci";
        type = "identity_availability_domain";
        dataSource = true;
        inputs = {
          inherit compartment_id;
          ad_number = var.oci_availability_domain.ref;
        };
      };
    };
    providers.oci = {
      inputs = with var; {
        tenancy_ocid = oci_tenancy.ref;
        user_ocid = oci_user.ref;
        private_key = oci_privkey.ref;
        #private_key_path = oci_privkey_file.ref;
        fingerprint = oci_fingerprint.ref;
        region = oci_region.ref;
      };
    };

    variables = let
      apivar = {
        type = "string";
        sensitive = true;
      };
    in {
      oci_region = apivar;
      oci_tenancy = apivar;
      oci_user = apivar;
      oci_privkey = apivar;
      oci_privkey_file = apivar;
      oci_fingerprint = apivar;
      oci_bucket = apivar;
      oci_compartment = apivar;
      oci_availability_domain = {
        type = "number";
        default = 1;
      };
    };

    example.serverAddr = "public_ip";

    nixos = { ... }: {
      imports = [
        ./oracle-image.nix
      ];
    };

    baseImage = { config, lib, pkgs, modulesPath, ... }: {
      imports = [
        ./oracle-image.nix
      ];

      config = {
        system.build.ociImage = import (modulesPath + "/../lib/make-disk-image.nix") {
          name = "oracle-oci-core-image";
          format = "qcow2-compressed"; # or qcow2
          diskSize = "auto"; # or MB
          partitionTableType = "legacy";
          label = "nixos";
          inherit config lib pkgs;
        };
      };
    };
  };

  options = {
    baseImage = mkOption {
      type = nixosType [ ];
    };

    # free plan requires it because image storage space isn't included
    nixosInfect = mkOption {
      type = types.bool;
      default = true;
    };
  };
}

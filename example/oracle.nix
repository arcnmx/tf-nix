{ lib, config, ... }: with lib; let
  inherit (config.lib.tf) terraformSelf;
  compartment_id = var.oci_compartment.ref;
  res = config.resources;
  var = config.variables;
  out = config.outputs;
  shape =
    if config.ampereA1 then "VM.Standard.A1.Flex"
    else "VM.Standard.E2.1.Micro";
  freeform_tags = {
    tfnix = true;
  };
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
            {
              content_type = "text/cloud-config";
              content = "#cloud-config\n" + builtins.toJSON {
                disable_root = false;
              };
            }
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
        } // optionalAttrs config.ampereA1 {
          shape_config = {
            memory_in_gbs = 1;
            ocpus = 1;
          };
        };
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
      oci_fingerprint = apivar;
      oci_bucket = apivar;
      oci_compartment = apivar;
      oci_availability_domain = {
        type = "number";
        default = 1;
      };
    };

    example.serverAddr = "public_ip";
    deploy.systems.system.lustrate.enable = config.nixosInfect;

    nixos = { ... }: {
      imports = [
        ./oracle-image.nix
      ];

      config = {
        nixpkgs = let
          armSystem = systems.examples.aarch64-multiplatform // {
            system = "aarch64-linux";
          };
        in mkIf config.ampereA1 {
          localSystem = mkIf config.nativeArm armSystem;
          crossSystem = mkIf (!config.nativeArm) armSystem;
        };
      };
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

    ampereA1 = mkOption {
      type = types.bool;
      default = false;
    };

    nativeArm = mkOption {
      description = "May require qemu-aarch64 binfmt handler registered on the host build machine";
      type = types.bool;
      default = true;
    };
  };
}

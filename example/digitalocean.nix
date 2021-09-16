{ lib, config, ... }: with lib; let
  inherit (config.lib.tf) terraformSelf;
  res = config.resources;
  lustrate = config.deploy.systems.system.lustrate.enable;
in {
  imports = [
    # common example system
    ./example.nix
  ];

  config = {
    # NOTE: if not using NIXOS_LUSTRATE, images must be uploaded manually, and can be built with:
    # nix-build '<tf>' -A baseImage.system.build.digitalOceanImage --arg config ./example/digitalocean.nix
    # ... then upload it via web interface as "nixos-image-example" as used below.
    deploy.systems.system.lustrate = {
      enable = true;
    };

    resources = {
      do_access = {
        provider = "digitalocean";
        type = "ssh_key";
        inputs = {
          name = "terraform/${config.nixos.networking.hostName} access key";
          public_key = res.access_key.refAttr "public_key_openssh";
        };
      };

      nixos_image = mkIf (!lustrate) {
        provider = "digitalocean";
        type = "image";
        dataSource = true;
        inputs.name = "nixos-image-example";
      };

      server = {
        provider = "digitalocean";
        type = "droplet";
        inputs = {
          image = if lustrate
            then "ubuntu-20-10-x64"
            else res.nixos_image.refAttr "id";
          name = "server";
          region = "tor1";
          size = "s-1vcpu-1gb";
          ssh_keys = singleton (res.do_access.refAttr "id");
        };
        connection = {
          host = terraformSelf "ipv4_address";
          ssh = {
            privateKey = res.access_key.refAttr "private_key_pem";
            privateKeyFile = res.access_file.refAttr "filename";
          };
        };
      };
    };

    variables.do_token = {
      type = "string";
      sensitive = true;
      # populate variable using https://www.passwordstore.org/
      #value.shellCommand = "pass show tokens/digitalocean";
    };

    providers.digitalocean = {
      inputs.token = config.variables.do_token.ref;
    };

    # configure the nixos image for use with DO's monitoring/networking/etc
    nixos = { tfModules, ... }: {
      imports = [
        tfModules.nixos.digitalocean
      ] ++ optional lustrate tfModules.nixos.ubuntu-linux;

      config = {
        virtualisation.digitalOcean = {
          rebuildFromUserData = false;
          metadataNetworking = lustrate;
        };
      };
    };
    baseImage = { tfModules, modulesPath, ... }: {
      imports = [
        (modulesPath + "/virtualisation/digital-ocean-image.nix")
        tfModules.nixos.digitalocean
      ];
      config = {
        virtualisation.digitalOceanImage.compressionMethod = "bzip2";
      };
    };
  };
  options = {
    baseImage = mkOption {
      type = nixosType [ ];
    };
  };
}

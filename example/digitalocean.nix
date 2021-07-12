{ config, ... }: let
  inherit (config.lib.tf) terraformSelf;
  res = config.resources;
in {
  imports = [
    # common example system
    ./example.nix
  ];

  config = {
    resources = {
      do_access = {
        provider = "digitalocean";
        type = "ssh_key";
        inputs = {
          name = "terraform/${config.nixos.networking.hostName} access key";
          public_key = res.access_key.refAttr "public_key_openssh";
        };
      };

      nixos_image = {
        provider = "digitalocean";
        type = "image";
        dataSource = true;
        # NOTE: must be uploaded manually because terraform doesn't support uploading images :<
        # nix-build '<tf>' -A config.baseImage.digitalOceanImage --arg config ./example/digitalocean.nix
        inputs.name = "nixos-image-example";
      };

      server = {
        provider = "digitalocean";
        type = "droplet";
        inputs = {
          image = res.nixos_image.refAttr "id";
          name = "server";
          region = "tor1";
          size = "s-1vcpu-2gb";
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
      # populate variable using https://www.passwordstore.org/
      #value.shellCommand = "pass show tokens/digitalocean";
    };

    providers.digitalocean = {
      inputs.token = config.variables.do_token.ref;
    };

    # configure the nixos image for use with DO's monitoring/networking/etc
    nixos = { modulesPath, ... }: {
      imports = [
        (modulesPath + "/virtualisation/digital-ocean-config.nix")
      ];
    };
    baseImage = { modulesPath, ... }: {
      imports = [
        (modulesPath + "/virtualisation/digital-ocean-image.nix")
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

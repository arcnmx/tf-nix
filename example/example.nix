{ config, lib, pkgs, tfModulesPath, ... }: with lib; let
  tf = config;
  res = config.resources;
in {
  config = {
    resources = {
      access_key = {
        provider = "tls";
        type = "private_key";
        inputs = {
          algorithm = "ECDSA";
          ecdsa_curve = "P384";
        };
      };

      access_file = {
        # shorthand to avoid specifying the provider:
        #type = "local.file";
        provider = "local";
        type = "file";
        inputs = {
          sensitive_content = res.access_key.refAttr "private_key_pem";
          filename = "${toString config.paths.dataDir}/access.private.pem";
          file_permission = "0500";
        };
      };

      secret = {
        provider = "random";
        type = "pet";
      };
    };

    outputs = {
      secret = {
        value = res.secret.refAttr "id";
        sensitive = true;
      };
    };

    nixos = { config, ... }: {
      config = {
        secrets = {
          # provided by <tf/modules/nixos>
          files.pet = {
            text = res.secret.refAttr "id";
          };
        };

        # terraform -> nix references
        users.users.root.openssh.authorizedKeys.keys = singleton (
          res.access_key.getAttr "public_key_openssh"
        );
        users.motd = ''
          welcome to ${res.server.getAttr tf.example.serverAddr}
          please don't look at ${config.secrets.files.pet.path}, it's private.
        '';
        security.pam.services.sshd.showMotd = true;
      };
    };
    deploy.systems.system = with config.resources; {
      nixosConfig = config.nixos;
      connection = server.connection.set;
      # if server gets replaced, make sure the deployment starts over
      triggers.copy.server = server.refAttr "id";
      triggers.secrets.server = server.refAttr "id";
    };
  };

  options = {
    nixos = mkOption {
      type = nixosType [ ];
    };
    example.serverAddr = mkOption {
      type = types.str;
      default = "ipv4_address";
    };
  };
}

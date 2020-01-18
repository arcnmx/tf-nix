{ config, lib, pkgs, ... }: with lib; let
  inherit (config.lib.tf) terraformProvider terraformReference terraformOutput terraformExpr terraformSelf terraformInput terraformNixStoreUrl nixRunWrapper hclDir;
  inherit (config) outputs;
in {
  imports = [
    ../modules/external.nix
  ];
  config = {
    resources = with config.resources; {
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
          sensitive_content = access_key.refAttr "private_key_pem";
          filename = "${toString config.paths.dataDir}/access.private.pem";
          file_permission = "0500";
        };
      };

      secret = {
        provider = "random";
        type = "pet";
      };

      do_access = {
        provider = "digitalocean";
        type = "ssh_key";
        inputs = {
          name = "terraform/${config.nixos.networking.hostName} access key";
          public_key = access_key.refAttr "public_key_openssh";
        };
      };

      nixos_unstable = {
        provider = "digitalocean";
        type = "image";
        dataSource = true;
        inputs.name = "nixos-unstable-2019-12-31-b38c2839917";
      };

      server = {
        provider = "digitalocean";
        type = "droplet";
        inputs = {
          image = nixos_unstable.refAttr "id";
          name = "server";
          region = "tor1";
          size = "s-1vcpu-2gb";
          ssh_keys = singleton (do_access.refAttr "id");
        };
        connection = {
          host = terraformSelf "ipv4_address";
          ssh = {
            privateKey = access_key.refAttr "private_key_pem";
            privateKeyFile = access_file.refAttr "filename";
          };
        };
      };

      server_nix_copy = {
        provider = "null";
        type = "resource";
        # intra-terraform reference
        connection = server.connection.set;
        inputs.triggers = {
          # TODO: pull in all command strings automatically!
          remote = server_nix_copy.connection.nixStoreUrl;
          system = config.nixos.system.build.toplevel;
        };

        # nix -> terraform reference
        provisioners = [ {
          # first check that remote is reachable (terraform includes more delay/retry logic than nix does)
          remote-exec.command = "true";
        } {
          # NOTE: `server.connection.nixStoreUrl` is incorrect here because it would contain references to `${self}` instead
          local-exec.command = "nix copy --substitute --to ${server_nix_copy.connection.nixStoreUrl} ${config.nixos.system.build.toplevel}";
        } {
          remote-exec.inline = [
            "nix-env -p /nix/var/nix/profiles/system --set ${config.nixos.system.build.toplevel}"
            "${config.nixos.system.build.toplevel}/bin/switch-to-configuration switch"
          ];
        } ];
      };
    };

    variables.do_token = {
      type = "string";
    };

    providers.digitalocean = {
      inputs.token = config.variables.do_token.ref;
    };

    outputs = with config.resources; {
      do_key.value = access_key.refAttr "public_key_openssh";
      motd.value = server.refAttr "ipv4_address";
      secret = {
        value = secret.refAttr "id";
        sensitive = true;
      };
    };

    run = with config.resources; {
      ssh = {
        command = "ssh -i ${access_file.getAttr "filename"} root@${server.getAttr "ipv4_address"}";
      };
    };

    nixos = { config, modulesPath, ... }: {
      imports = [
        # TODO: ugh needs https://github.com/NixOS/nixpkgs/pull/75031
        (modulesPath + "/virtualisation/digital-ocean-config.nix")
        ../nixos/secrets.nix
      ];

      config = {
        secrets = {
          files.pet = {
            text = outputs.secret.get;
          };
          external = true;
        };

        # terraform -> nix references
        users.users.root.openssh.authorizedKeys.keys = singleton outputs.do_key.get;
        users.motd = ''
          welcome to ${outputs.motd.get}
          please don't look at ${config.secrets.files.pet.path}, it's private.
        '';
        security.pam.services.sshd.showMotd = true;

        # slim build
        documentation.enable = false;
      };
    };
    secrets.deploy = [
      {
        nixosConfig = config.nixos;
        connection = config.resources.server.connection.set;
      }
    ];
  };

  options = {
    nixos = mkOption {
      type = nixosType [ ];
    };
  };
}

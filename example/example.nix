{ config, lib, pkgs, ... }: with lib; let
  inherit (config.terraform.lib.tf) terraformProvider terraformReference terraformOutput terraformExpr terraformInput terraformConnectionDetails terraformNixStoreUrl;
  inherit (config) outputs;
in {
  config = {
    terraform = {
      resources = with config.terraform.resources; {
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
            sensitive_content = access_key.referenceAttr "private_key_pem";
            filename = "${terraformExpr "path.cwd"}/access.private.pem";
            file_permission = "0500";
          };
        };

        do_access = {
          provider = "digitalocean";
          type = "ssh_key";
          inputs = {
            name = "terraform/${config.nixos.networking.hostName} access key";
            public_key = access_key.referenceAttr "public_key_openssh";
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
            image = nixos_unstable.referenceAttr "id";
            name = "server";
            region = "tor1";
            size = "s-1vcpu-2gb";
            ssh_keys = singleton (do_access.referenceAttr "id");
          };
          connection = terraformConnectionDetails {
            host = server.referenceAttr "ipv4_address";
            privateKey = access_key.referenceAttr "private_key_pem";
            privateKeyFile = access_file.referenceAttr "filename";
          };
        };

        example = {
          provider = "digitalocean";
          type = "domain";
          inputs.name = "example.com";
        };

        www = {
          provider = "digitalocean";
          type = "record";
          inputs = {
            type = "A";
            name = "www";
            # intra-terraform reference
            domain = example.referenceAttr "name";
            value = server.referenceAttr "ipv4_address";
          };
        };

        server_nix_copy = {
          provider = "null";
          type = "resource";
          # intra-terraform reference
          connection = server.connection;
          inputs.triggers = {
            # TODO: pull in all command strings automatically!
            remote = url;
            system = config.nixos.system.build.toplevel;
          };

          # nix -> terraform reference
          provisioners = [ {
            local-exec.command = "nix copy --substitute --to ${server.connection.nixStoreUrl} ${config.nixos.system.build.toplevel}";
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
        inputs.token = config.terraform.variables.do_token.ref;
      };

      outputs = with config.terraform.resources; {
        do_key.value = access.referenceAttr "public_key_openssh";
        motd.value = server.referenceAttr "ipv4_address";
      };

      targets = {
        server = [
          "server_nix_copy"
        ];
      };
    };

    nixos = { modulesPath, ... }: {
      imports = [
        # TODO: ugh needs https://github.com/NixOS/nixpkgs/pull/75031
        (modulesPath + "/virtualisation/digital-ocean-config.nix")
      ];
      #boot.isContainer = true;

      # terraform -> nix references
      users.users.root.openssh.authorizedKeys.keys = singleton outputs.do_key.ref;
      users.motd = "welcome to ${outputs.motd.ref}";
      #services.nginx = {
      #  # terraform -> nix reference
      #  bindIp = terraformOutput "resource.something_server.server" "ip";
      #};
    };
  };
}

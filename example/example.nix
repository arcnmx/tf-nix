{ config, lib, pkgs, ... }: with lib; let
  inherit (config.nixos.lib.terranix) terraformProvider terraformReference terraformOutput terraformExpr terraformInput terraformConnectionDetails terraformNixStoreUrl;
in {
  config = {
    terraform = {
      resource.tls_private_key.access = {
        algorithm = "ECDSA";
        ecdsa_curve = "P384";
      };

      resource.local_file.access_key = {
        sensitive_content = terraformOutput "resource.tls_private_key.access" "private_key_pem";
        filename = "${terraformExpr "path.cwd"}/access.private.pem";
        file_permission = "0500";
      };

      resource.digitalocean_ssh_key.access = {
        provider = terraformProvider "digitalocean" "default";
        name = "terraform/${config.nixos.networking.hostName} access key";
        public_key = terraformOutput "resource.tls_private_key.access" "public_key_openssh";
      };

      data.digitalocean_image.nixos_unstable = {
        provider = terraformProvider "digitalocean" "default";
        name = "nixos-unstable-2019-12-31-b38c2839917";
      };

      variable.do_token = { };
      # "default" provider is a special-cased string
      provider.digitalocean.default = {
        token = terraformInput "do_token";
      };
      resource.digitalocean_droplet.server = {
        # unnecessary if using "default" provider
        provider = terraformProvider "digitalocean" "default";
        image = terraformOutput "data.digitalocean_image.nixos_unstable" "id";
        name = "server";
        region = "tor1";
        size = "s-1vcpu-2gb";
        ssh_keys = singleton (terraformOutput "resource.digitalocean_ssh_key.access" "id");
      };

      resource.digitalocean_domain.default = {
        provider = terraformProvider "digitalocean" "default";
        name = "example.com";
      };

      resource.digitalocean_record.www = {
        provider = terraformProvider "digitalocean" "default";
        domain = terraformOutput "resource.digitalocean_domain.default" "name";
        type = "A";
        name = "www";
        # intra-terraform reference
        value = terraformOutput "resource.digitalocean_droplet.server" "ipv4_address";
      };

      resource.null_resource.server_nix_copy = let
        url = terraformNixStoreUrl {
          resource = "resource.digitalocean_droplet.server";
          private_key_file = terraformOutput "resource.local_file.access_key" "filename";
        };
      in {
        # intra-terraform reference
        connection = terraformConnectionDetails {
          resource = "resource.digitalocean_droplet.server";
          private_key = terraformOutput "resource.tls_private_key.access" "private_key_pem";
        };
        triggers = {
          # TODO: pull in all command strings automatically!
          remote = url;
          system = config.nixos.system.build.toplevel;
        };

        # nix -> terraform reference
        provisioner = [ {
          local-exec.command = "nix copy --substitute --to ${url} ${config.nixos.system.build.toplevel}";
        } {
          remote-exec.inline = [
            "nix-env -p /nix/var/nix/profiles/system --set ${config.nixos.system.build.toplevel}"
            "${config.nixos.system.build.toplevel}/bin/switch-to-configuration switch"
          ];
        } ];
      };
    };

    terranix = {
      #gcroots = [ "provider.digitalocean" ]; # TODO: determine these automatically
      targets = {
        server = [
          "resource.null_resource.server_nix_copy"
        ];
      };
    };

    nixos = { ... }: {
      #imports = [
      #  <nixpkgs/nixos/modules/virtualisation/digital-ocean-config.nix> # TODO: ugh
      #];
      boot.isContainer = true;

      users.users.root.openssh.authorizedKeys.keys = singleton (terraformReference "resource.digitalocean_ssh_key.access" "public_key_openssh");
      # terraform -> nix reference
      users.motd = "welcome to ${terraformReference "resource.digitalocean_droplet.server" "ipv4_address"}";
      #services.nginx = {
      #  # terraform -> nix reference
      #  bindIp = terraformOutput "resource.something_server.server" "ip";
      #};
    };
  };
}

{ modulesPath, pkgs, config, lib, ... }: with lib; let
  cfg = config.virtualisation.digitalOcean;
in {
  imports = [
    ./vm.nix
    (modulesPath + "/virtualisation/digital-ocean-config.nix")
  ];

  options.virtualisation.digitalOcean = {
    metadataNetworking = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to instantiate networking config from Digital Ocean metadata";
    };
  };

  config = {
    boot.initrd.availableKernelModules = [
      "nvme"
    ];
    networking.interfaces.eth0 = mkIf cfg.metadataNetworking {
      ipv4 = {
        addresses = [
          {
            address = "169.254.0.1";
            prefixLength = 16;
          }
        ];
        routes = [
          {
            address = "169.254.169.254";
            prefixLength = 32;
          }
        ];
      };
    };
    systemd.services.digitalocean-network = mkIf cfg.metadataNetworking {
      path = [ pkgs.iproute pkgs.jq ];
      wantedBy = [ "network.target" ];
      description = "DigitalOcean static network configuration";
      script = ''
        set -xeo pipefail
        netmask() {
          # https://stackoverflow.com/a/50414560
          c=0 x=0$( printf '%o' ''${1//./ } )
          while [ $x -gt 0 ]; do
              let c+=$((x%2)) 'x>>=1'
          done
          echo /$c
        }
        META=/run/do-metadata/v1.json
        IPV4=$(jq -er '.interfaces.public[0].ipv4.ip_address' $META)
        NETMASK=$(jq -er '.interfaces.public[0].ipv4.netmask' $META)
        GATEWAY=$(jq -er '.interfaces.public[0].ipv4.gateway' $META)
        NAMESERVERS=$(jq -er '.dns.nameservers | .[]' $META)
        ip addr add $IPV4$(netmask $NETMASK) dev eth0
        ip route add default via $GATEWAY dev eth0
        for ns in $NAMESERVERS; do
          echo "nameserver $ns" >> /etc/resolv.conf
        done
      '';
      unitConfig = {
        Before = [ "network.target" ];
        After = [ "digitalocean-metadata.service" ];
        Requires = [ "digitalocean-metadata.service" ];
      };
      serviceConfig = {
        Type = "oneshot";
      };
    };
  };
}

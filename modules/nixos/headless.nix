{ pkgs, config, lib, modulesPath, ... }: with lib; {
  options = {
    services.openssh.sha1LegacyCompatability = mkOption {
      type = types.bool;
      default = versionAtLeast config.programs.ssh.package.version "8.8";
      description = ''
        Allow signing clients to use the deprecated RSA/SHA1 algorithm to authenticate, which is
        still required at this time by Go applications such as Terraform.
      '';
    };
  };
  config = {
    boot = {
      vesa = mkDefault false;
    };

    systemd.services."getty@tty1".enable = mkDefault false;
    systemd.services."autovt@".enable = mkDefault false;
    systemd.enableEmergencyMode = mkDefault false;

    services.openssh = {
      enable = mkDefault true;
      extraConfig = mkIf config.services.openssh.sha1LegacyCompatability ''
        # workaround for terraform (see https://github.com/golang/go/issues/39885)
        PubkeyAcceptedAlgorithms +ssh-rsa
      '';
    };

    # slim build
    documentation.enable = mkDefault false;
    services.udisks2.enable = mkDefault false;

    environment.variables = {
      GC_INITIAL_HEAP_SIZE = mkDefault "8M"; # nix default is way too big
    };
  };
}

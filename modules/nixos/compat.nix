{ config, lib, ... }: with lib; {
  options = {
    services.openssh.sha1LegacyCompatibility = mkOption {
      type = types.bool;
      default = versionAtLeast config.programs.ssh.package.version "8.8";
      description = ''
        Allow signing clients to use the deprecated RSA/SHA1 algorithm to authenticate, which is
        still required at this time by Go applications such as Terraform.
      '';
    };
  };
  config = {
    services.openssh.extraConfig = mkIf config.services.openssh.sha1LegacyCompatibility ''
      # workaround for terraform (see https://github.com/golang/go/issues/39885)
      PubkeyAcceptedAlgorithms +ssh-rsa
    '';
  };
}

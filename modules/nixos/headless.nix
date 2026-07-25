{ lib, ... }: with lib; {
  config = {
    boot = {
      ${if lib.versionOlder lib.version "26.05" then "vesa" else null} = mkDefault false;
    };

    systemd.services."getty@tty1".enable = mkDefault false;
    systemd.services."autovt@".enable = mkDefault false;
    systemd.enableEmergencyMode = mkDefault false;

    services.openssh = {
      enable = mkDefault true;
    };

    # slim build
    documentation.enable = mkDefault false;
    services.udisks2.enable = mkDefault false;

    environment.variables = {
      GC_INITIAL_HEAP_SIZE = mkDefault "8M"; # nix default is way too big
    };
  };
}

{ config, lib, ... }: with lib; {
  config = {
    boot = {
      loader.grub = mkIf (!config.boot.loader.grub.efiSupport) {
        device = mkDefault "/dev/sda";
      };
    };

    fileSystems = {
      "/" = {
        device = mkDefault "/dev/sda3";
        fsType = mkDefault "xfs";
      };
      "/boot" = mkIf config.boot.loader.grub.efiSupport {
        device = mkDefault "/dev/disk/by-partlabel/EFI\\x20System\\x20Partition";
        fsType = mkDefault "vfat";
      };
    };

    swapDevices = [
      {
        device = "/dev/sda2";
      }
    ];
  };
}

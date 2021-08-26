{ config, lib, ... }: with lib; {
  config = {
    boot = {
      loader.grub = mkIf (!config.boot.loader.grub.efiSupport) {
        device = mkDefault "/dev/sda";
      };
    };

    fileSystems = {
      "/" = {
        device = mkDefault "/dev/disk/by-label/cloudimg-rootfs";
        fsType = mkDefault "ext4";
      };
      "/boot" = mkIf config.boot.loader.grub.efiSupport {
        device = mkDefault "/dev/disk/by-label/UEFI";
        fsType = mkDefault "vfat";
      };
    };
  };
}

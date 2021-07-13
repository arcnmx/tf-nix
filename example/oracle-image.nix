{ lib, modulesPath, ... }: with lib; let
  image = false;
  efi = !image;
  lustrateHost = "ubuntu";
in {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    #(modulesPath + "/profiles/headless.nix")
    #(modulesPath + "/virtualisation/qemu-vm.nix")
  ];

  config = {
    services = {
      cloud-init.enable = image;
      getty.autologinUser = "root"; # FOR TESTING REMOVEME!!!
    };

    environment = {
      variables = {
        GC_INITIAL_HEAP_SIZE = mkDefault "8M"; # nix default is way too big
      };
    };

    boot = {
      growPartition = true;
      kernelParams = [
        "panic=30" "boot.panic_on_fail"
        "console=ttyS0"
        "console=tty1"
      ];
      #kernel.sysctl = {
      #  "vm.overcommit_memory" = "1";
      #};
      loader = {
        grub = if efi then {
          efiSupport = true;
          efiInstallAsRemovable = true;
          device = "nodev";
        } else {
          device = "/dev/sda";
        };
        timeout = 0;
      };
      initrd = {
        availableKernelModules = [
          "nvme" "ata_piix" "uhci_hcd"
        ];
      };
    };

    fileSystems = {
      "/" = if image then {
        device = "/dev/disk/by-label/nixos";
        fsType = "ext4";
        autoResize = true;
      } else {
        device = {
          ubuntu = "/dev/disk/by-label/cloudimg-rootfs";
          oracle = "/dev/sda3";
        }.${lustrateHost} or (throw "unknown host disk");
        fsType = {
          ubuntu = "ext4";
          oracle = "xfs";
        }.${lustrateHost} or (throw "unknown host fs");
      };
      "/boot" = mkIf efi (if image then {
        device = "/dev/disk/by-label/ESP";
        fsType = "vfat";
      } else {
        device = {
          ubuntu = "/dev/disk/by-label/UEFI";
          oracle = "/dev/disk/by-partlabel/EFI\\x20System\\x20Partition";
        }.${lustrateHost} or (throw "unknown host disk");
        fsType = "vfat";
      });
    };

    swapDevices = [ {
      device = "/swapfile";
      size = mkDefault 2048; # MB
    } ] ++ optional (false) {
      # exists on ampere arm oracle linux systems?
      device = "/dev/sda2";
    };

    networking = {
      hostName = mkDefault "";
    };
  };
}

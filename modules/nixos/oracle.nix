{ lib, ... }: with lib; {
  imports = [
    ./vm.nix
  ];

  config = {
    boot = {
      loader.grub.efiSupport = mkDefault true;
      initrd.availableKernelModules = [
        "nvme" "ata_piix" "uhci_hcd"
      ];
    };
  };
}

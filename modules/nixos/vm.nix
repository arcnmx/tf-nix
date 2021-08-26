{ pkgs, config, lib, modulesPath, ... }: with lib; {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ./headless.nix
  ];

  config = {
    boot = {
      kernelParams = mkMerge [
        [
          "panic=30" "boot.panic_on_fail"
        ]
        (mkIf pkgs.hostPlatform.isx86 [
          "console=ttyS0"
        ])
        (mkIf pkgs.hostPlatform.isAarch64 [
          "console=ttyAMA0"
        ])
      ];
      growPartition = mkDefault true;
      loader.grub = mkIf config.boot.loader.grub.efiSupport {
        efiInstallAsRemovable = mkDefault true;
        device = mkDefault "nodev";
      };
    };

    networking = {
      hostName = mkDefault "";
    };
  };
}

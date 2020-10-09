{ config, lib, ... }: with lib; let
  cfg = config.secrets;
in {
  options.secrets.userConfigs = mkOption {
    type = types.listOf types.unspecified;
    default = [ ];
  };

  config.secrets = {
    userConfigs = mkIf (options ? home-manager.users) (mkDefault (attrValues config.home-manager.users));
    files = mkMerge (map (user: mapAttrs' (k: file:
      nameValuePair "user-${user.home.username}-${k}" file.out.set
    ) user.secrets.files) cfg.userConfigs);
  };
}

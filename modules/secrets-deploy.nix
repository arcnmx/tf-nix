{ config, lib, ... }: with lib; let
  cfg = config.secrets.deploy;
in {
  options = {
    secrets = {
      deploy = {
        nixosConfigs = mkOption {
          type = types.listOf types.unspecified;
          default = [ ];
        };
        files = mkOption {
          type = types.listOf types.unspecified;
        };
        refIds = mkOption {
          type = types.separatedString "";
          default = "";
        };
      };
    };
  };

  config = {
    secrets.deploy = {
      files = concatMap (config: attrValues config.secrets.files) cfg.nixosConfigs;
      refIds = mkMerge (map (file: config.resources.${file.out.tf.key}.refAttr "id") cfg.files);
    };
    resources = listToAttrs (map (file: nameValuePair file.out.tf.key file.out.tf.setResource) cfg.files);
  };
}

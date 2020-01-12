{ config, lib, ... }: with lib; let
  secretsType = types.submodule ({ ... }: {
    options = {
      nixosConfig = mkOption {
        type = types.unspecified;
      };
      connection = mkOption {
        type = types.unspecified;
      };
    };
  });
in {
  options = {
    secrets = {
      deploy = mkOption {
        type = types.listOf secretsType;
        default = [ ];
      };
    };
  };

  config = {
    resources = listToAttrs (concatMap (sec: mapAttrsToList (k: file: nameValuePair "secrets_${sec.nixosConfig.networking.hostName}_${k}" {
      provider = "null";
      type = "resource";
      connection = sec.connection;
      inputs.triggers = {
        inherit (file) path sha256;
      };
      provisioners = [
        {
          remote-exec.command = ''
            mkdir -m ${file.mode} -p "${file.out.dir}"
          '';
        }
        {
          file = {
            destination = file.path;
          } // (if file.text != null then {
            content = file.text;
          } else {
            source = toString file.source;
          });
        }
        {
          remote-exec.command = ''
            chown ${file.owner}:${file.group} "${file.out.dir}"
          '';
        }
      ];
    }) sec.nixosConfig.secrets.files) config.secrets.deploy);
  };
}

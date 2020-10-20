{ config, lib, ... }: with lib; let
  config' = config;
  cfg = config.acme;
in {
  options.acme = {
    enable = mkOption {
      type = types.bool;
    };
    account = {
      accountKeyPem = mkOption {
        type = types.str;
      };
      emailAddress = mkOption {
        type = types.str;
      };
      register = mkOption {
        type = types.bool;
        default = false;
      };
      provider = mkOption {
        type = config.lib.tf.tfTypes.providerReferenceType;
        default = "acme";
      };
      resourceName = mkOption {
        type = types.str;
        default = "acme_account";
      };
    };
    challenge = {
      defaultProvider = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      configs = mkOption {
        type = types.attrsOf (types.attrsOf types.unspecified);
        default = { };
      };
    };
    certs = mkOption {
      type = types.attrsOf (types.submodule ({ name, config, ... }: {
        options = {
          name = mkOption {
            type = types.str;
            default = name;
          };
          dnsNames = mkOption {
            type = types.listOf types.str;
          };
          keyType = mkOption {
            type = types.enum [ "2048" "4096" "8192" "P256" "P384" ];
            default = "2048";
          };
          mustStaple = mkOption {
            type = types.bool;
            default = false;
          };
          minDaysRemaining = mkOption {
            type = types.int;
            default = 30;
          };
          challenge = {
            provider = mkOption {
              type = types.str;
            };
            config = mkOption {
              type = types.attrsOf types.unspecified;
              default = cfg.challenge.configs.${config.challenge.provider} or { };
            };
          };
          out = {
            commonName = mkOption {
              type = types.unspecified;
              internal = true;
              readOnly = true;
            };
            subjectAlternateNames = mkOption {
              type = types.unspecified;
              internal = true;
              readOnly = true;
            };
            resource = mkOption {
              type = types.unspecified;
              internal = true;
              readOnly = true;
            };
            resourceName = mkOption {
              type = types.str;
              internal = true;
              readOnly = true;
            };
            importFullchainPem = mkOption {
              type = types.unspecified;
              readOnly = true;
            };
            getFullchainPem = mkOption {
              type = types.unspecified;
              readOnly = true;
            };
            refFullchainPem = mkOption {
              type = types.unspecified;
              readOnly = true;
            };
            importPrivateKeyPem = mkOption {
              type = types.unspecified;
              readOnly = true;
            };
            getPrivateKeyPem = mkOption {
              type = types.unspecified;
              readOnly = true;
            };
            refPrivateKeyPem = mkOption {
              type = types.unspecified;
              readOnly = true;
            };
            set = mkOption {
              type = types.attrsOf types.unspecified;
              internal = true;
              readOnly = true;
            };
          };
        };
        config = {
          challenge.provider = mkIf (cfg.challenge.defaultProvider != null) cfg.challenge.defaultProvider;
          out = {
            commonName = head config.dnsNames;
            subjectAlternateNames = tail config.dnsNames;
            resourceName = let
              name = config'.lib.tf.terraformIdent config.name;
            in mkOptionDefault "${cfg.account.provider.type}_${name}";
            resource = config'.resources.${config.out.resourceName};
            importFullchainPem = config.out.resource.importAttr "certificate_pem" + config.out.resource.importAttr "issuer_pem";
            getFullchainPem = config.out.resource.getAttr "certificate_pem" + config.out.resource.getAttr "issuer_pem";
            refFullchainPem = config.out.resource.refAttr "certificate_pem" + config.out.resource.refAttr "issuer_pem";
            importPrivateKeyPem = config.out.resource.importAttr "private_key_pem"; # TODO: if certificate_request_pem used, get this from the request key instead
            getPrivateKeyPem = config.out.resource.getAttr "private_key_pem"; # TODO: if certificate_request_pem used, get this from the request key instead
            refPrivateKeyPem = config.out.resource.refAttr "private_key_pem"; # TODO: if certificate_request_pem used, get this from the request key instead
            set = {
              provider = "acme";
              type = "certificate";
              inputs = {
                account_key_pem = cfg.account.accountKeyPem;
                key_type = config.keyType;
                common_name = config.out.commonName;
                subject_alternative_names = config.out.subjectAlternateNames;
                must_staple = config.mustStaple;
                min_days_remaining = config.minDaysRemaining;
                dns_challenge = {
                  inherit (config.challenge) provider config;
                };
              };
              dependsOn = mkIf cfg.account.register [ config'.resources.${cfg.account.resourceName}.namedRef ];
            };
          };
        };
      }));
      default = { };
    };
  };
  config = {
    acme = {
      enable = mkOptionDefault (cfg.certs != { } || cfg.account.register);
      account = mkIf cfg.enable {
        accountKeyPem = mkIf cfg.account.register (mkOptionDefault
          (config.resources.${cfg.account.resourceName}.refAttr "account_key_pem")
        );
      };
    };
    providers = mkIf cfg.enable {
      ${cfg.account.provider.out.name} = {
        type = mkDefault cfg.account.provider.type;
        inputs.server_url = mkDefault "https://acme-v02.api.letsencrypt.org/directory";
      };
    };
    resources = mkIf cfg.enable (mkMerge [
      (mapAttrs' (_: value: nameValuePair value.out.resourceName value.out.set) cfg.certs)
      (mkIf cfg.account.register {
        ${cfg.account.resourceName} = {
          provider = cfg.account.provider.set;
          type = "registration";
          inputs = {
            email_address = cfg.account.emailAddress;
            account_key_pem = cfg.account.accountKeyPem;
          };
        };
      })
    ]);
  };
  # TODO: all the rest
}

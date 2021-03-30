{ config, lib, ... }: with lib; let
  cfg = config.dns;
  tfconfig = config;
  zoneType = types.submodule ({ name, config, ... }: {
    options = {
      tld = mkOption {
        type = types.str;
        default = name;
      };
      provider = mkOption {
        type = tfconfig.lib.tf.tfTypes.providerReferenceType;
      };
      create = mkOption {
        type = types.bool;
        default = true;
      };
      dataSource = mkOption {
        type = types.bool;
        default = false;
      };
      inputs = mkOption {
        type = types.attrsOf types.unspecified;
        default = false;
      };
      cloudflare.id = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      out = {
        resourceName = mkOption {
          type = types.str;
          internal = true;
          readOnly = true;
        };
        resource = mkOption {
          type = types.unspecified;
          internal = true;
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
      provider = mkIf (config.cloudflare.id != null) (mkOptionDefault "cloudflare");
      create = mkMerge [
        (mkIf (config.cloudflare.id != null) (mkDefault false))
        (mkIf (config.provider.type == "dns") (mkDefault false))
      ];
      out = {
        resourceName = let
          tld = tfconfig.lib.tf.terraformIdent config.tld;
        in mkOptionDefault "${config.provider.type}_${tld}";
        resource = tfconfig.resources.${config.out.resourceName};
        set = {
          provider = config.provider.set;
          inherit (config) dataSource;
        } // {
          cloudflare = if config.dataSource then {
            type = "zones";
            inputs.filter.name = config.tld;
          } else {
            type = "zone";
            inputs = {
              zone = config.tld;
            } // config.inputs;
          };
          dns = { };
        }.${config.provider.type};
      };
    };
  });
  recordType = types.submodule ({ name, config, ... }: {
    options = {
      name = mkOption {
        type = types.str;
        default = name;
      };
      tld = mkOption {
        type = types.str;
      };
      domain = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      ttl = mkOption {
        type = types.int;
        default = 3600;
      };
      a = mkOption {
        type = types.nullOr (types.submodule ({ config, ... }: {
          options = {
            address = mkOption {
              type = types.str;
            };
          };
        }));
        default = null;
      };
      aaaa = mkOption {
        type = types.nullOr (types.submodule ({ config, ... }: {
          options = {
            address = mkOption {
              type = types.str;
            };
          };
        }));
        default = null;
      };
      cname = mkOption {
        type = types.nullOr (types.submodule ({ config, ... }: {
          options = {
            target = mkOption {
              type = types.str;
            };
          };
        }));
        default = null;
      };
      srv = mkOption {
        type = types.nullOr (types.submodule ({ config, ... }: {
          options = {
            service = mkOption {
              type = types.str;
            };
            proto = mkOption {
              type = types.str;
              default = "tcp";
            };
            priority = mkOption {
              type = types.int;
              default = 0;
            };
            weight = mkOption {
              type = types.int;
              default = 5;
            };
            port = mkOption {
              type = types.port;
            };
            target = mkOption {
              type = types.str;
            };
          };
        }));
        default = null;
      };
      out = {
        type = mkOption {
          type = types.str;
          internal = true;
          readOnly = true;
        };
        resourceName = mkOption {
          type = types.str;
          internal = true;
          readOnly = true;
        };
        domain = mkOption {
          type = types.str;
          internal = true;
          readOnly = true;
        };
        fqdn = mkOption {
          type = types.str;
          internal = true;
          readOnly = true;
        };
        resource = mkOption {
          type = types.unspecified;
          internal = true;
          readOnly = true;
        };
        zone = mkOption {
          type = types.unspecified;
          internal = true;
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
      out = {
        type = let
          types = filter (t: t != null) [
            (mapNullable (_: "SRV") config.srv)
            (mapNullable (_: "A") config.a)
            (mapNullable (_: "AAAA") config.aaaa)
            (mapNullable (_: "CNAME") config.cname)
          ];
        in if length types == 1 then mkOptionDefault (head types)
          else throw "invalid DNS record type";
        resourceName = let
          tld = replaceStrings [ "-" "." ] [ "_" "_" ] config.name;
        in mkOptionDefault "record_${tld}_${config.out.type}";
        domain = if config.domain == null then "@" else config.domain;
        fqdn = if config.domain == null then config.tld else "${config.domain}.${config.tld}";
        resource = tfconfig.resources.${config.out.resourceName};
        zone = cfg.zones.${config.tld};
        set = {
          cloudflare = {
            provider = config.out.zone.provider.set;
            type = "record";
            inputs = {
              zone_id = if config.out.zone.cloudflare.id != null
                then config.out.zone.cloudflare.id
                else if config.out.zone.dataSource
                then config.out.zone.out.resource.refAttr ''zones[0]["id"]''
                else config.out.zone.out.resource.refAttr "id";
              inherit (config.out) type;
              name = config.out.domain;
            } // (if config.out.type == "SRV" then {
              data = {
                service = "_${config.srv.service}";
                proto = "_${config.srv.proto}";
                name = config.out.domain;
                inherit (config.srv) priority weight port target;
              };
            } else if config.out.type == "A" then {
              value = config.a.address;
            } else if config.out.type == "AAAA" then {
              value = config.aaaa.address;
            } else if config.out.type == "CNAME" then {
              value = config.cname.target;
            } else throw "unknown DNS record ${config.out.type}");
          };
          dns = let
            name = config.out.domain;
            zone = config.out.zone.tld;
          in {
            provider = config.out.zone.provider.set;
            type = "${toLower config.out.type}_record"
              + optionalString (config.out.type != "CNAME" && config.out.type != "PTR") "_set";
            inputs = {
              A = {
                inherit zone name;
                inherit (config) ttl;
                addresses = singleton config.a.address;
              };
              AAAA = {
                inherit zone name;
                inherit (config) ttl;
                addresses = singleton config.aaaa.address;
              };
              CNAME = {
                inherit zone name;
                inherit (config) ttl;
                cname = config.cname.target;
              };
              SRV = {
                inherit zone;
                name = "_${config.srv.service}._${config.srv.proto}";
                inherit (config) ttl;
                srv = singleton {
                  inherit (config.srv) priority weight port target;
                };
              };
            }.${config.out.type} or (throw "Unsupported record type ${config.out.type}");
          };
        }.${config.out.zone.provider.type} or (throw "Unknown provider ${config.out.zone.provider.type}");
      };
    };
  });
in {
  options.dns = {
    zones = mkOption {
      type = types.attrsOf zoneType;
      default = { };
    };
    records = mkOption {
      type = types.attrsOf recordType;
      default = { };
    };
  };
  config.resources =
    mapAttrs' (name: cfg: nameValuePair cfg.out.resourceName cfg.out.set) (filterAttrs (_: z: z.create) cfg.zones)
    // mapAttrs' (name: cfg: nameValuePair cfg.out.resourceName cfg.out.set) cfg.records;
}

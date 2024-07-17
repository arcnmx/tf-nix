{ config, lib, ... }: with lib; let
  cfg = config.dns;
  tflib = config.lib.tf;
  inherit (config) resources;
  warnings = mkOption {
    # mkAliasOptionModule sets these
    type = with types; listOf str;
    internal = true;
    default = [ ];
  };
  zoneType = types.submodule ({ name, config, ... }: {
    imports = [
      (mkRenamedOptionModule [ "tld" ] [ "domain" ])
      (mkAliasOptionModule [ "zone" ] [ "domain" ])
    ];
    options = {
      enable = mkEnableOption "dns zone" // {
        default = true;
      };
      domain = mkOption {
        type = types.str;
        default = name;
      };
      provider = mkOption {
        type = tflib.tfTypes.providerReferenceType;
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
        set = {
          provider = mkOption {
            type = types.unspecified;
            internal = true;
            readOnly = true;
          };
          type = mkOption {
            type = types.str;
            internal = true;
            readOnly = true;
          };
          inputs = mkOption {
            type = types.attrs;
            internal = true;
            readOnly = true;
          };
        };
      };
      inherit warnings;
    };
    config = {
      provider = mkIf (config.cloudflare.id != null) (mkOptionDefault "cloudflare");
      create = mkMerge [
        (mkIf (config.cloudflare.id != null) (mkDefault false))
        (mkIf (config.provider.type == "dns") (mkDefault false))
      ];
      out = {
        resourceName = let
          domain = tflib.terraformIdent config.domain;
        in mkOptionDefault "${config.provider.type}_${domain}";
        resource = resources.${config.out.resourceName};
        set = {
          provider = config.provider.set;
        } // {
          cloudflare = if config.dataSource then {
            type = "zones";
            inputs.filter.name = config.domain;
          } else {
            type = "zone";
            inputs = {
              zone = config.domain;
            } // config.inputs;
          };
          dns = { };
        }.${config.provider.type};
      };
    };
  });
  recordType = types.submodule ({ name, config, ... }: {
    imports = [
      (mkRenamedOptionModule [ "tld" ] [ "zone" ])
    ];
    options = {
      enable = mkEnableOption "dns record" // {
        default = true;
      };
      name = mkOption {
        type = types.str;
        default = name;
      };
      zone = mkOption {
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
      mx = mkOption {
        type = types.nullOr (types.submodule ({ config, ... }: {
          options = {
            target = mkOption {
              type = types.str;
            };
            priority = mkOption {
              type = types.int;
              default = 10;
            };
          };
        }));
        default = null;
      };
      txt = mkOption {
        type = types.nullOr (types.submodule ({ config, ... }: {
          options = {
            value = mkOption {
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
      uri = mkOption {
        type = types.nullOr (types.submodule ({ config, ... }: {
          options = {
            service = mkOption {
              type = types.str;
            };
            proto = mkOption {
              type = types.nullOr types.str;
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
        set = {
          provider = mkOption {
            type = types.unspecified;
            internal = true;
            readOnly = true;
          };
          type = mkOption {
            type = types.str;
            internal = true;
            readOnly = true;
          };
          inputs = mkOption {
            type = types.attrs;
            internal = true;
            readOnly = true;
          };
        };
      };
      inherit warnings;
    };
    config = {
      out = {
        type = let
          types = filter (t: t != null) [
            (mapNullable (_: "SRV") config.srv)
            (mapNullable (_: "URI") config.uri)
            (mapNullable (_: "A") config.a)
            (mapNullable (_: "AAAA") config.aaaa)
            (mapNullable (_: "CNAME") config.cname)
            (mapNullable (_: "MX") config.mx)
            (mapNullable (_: "TXT") config.txt)
          ];
        in if length types == 1 then mkOptionDefault (head types)
          else throw "invalid DNS record type";
        resourceName = let
          name = replaceStrings [ "-" "." ] [ "_" "_" ] config.name;
        in mkOptionDefault "record_${name}_${config.out.type}";
        domain = if config.domain == null then "@" else config.domain;
        fqdn = optionalString (config.domain != null) "${config.domain}." + config.zone;
        resource = resources.${config.out.resourceName};
        zone = cfg.zones.${config.zone};
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
              name = concatStringsSep "." ([
                "_${config.srv.service}"
                "_${config.srv.proto}"
              ] ++ optional (config.domain != null) config.domain
              #++ [ config.out.fqdn ]
              );
              data = {
                inherit (config.srv) priority weight port target;
              };
            } else if config.out.type == "URI" then {
              data = {
                service = "_${config.uri.service}";
                ${mapNullable (_: "proto") config.uri.proto} = "_${config.uri.proto}";
                name = config.out.fqdn;
                inherit (config.uri) priority weight target;
              };
            } else if config.out.type == "A" then {
              value = config.a.address;
            } else if config.out.type == "AAAA" then {
              value = config.aaaa.address;
            } else if config.out.type == "CNAME" then {
              value = config.cname.target;
            } else if config.out.type == "MX" then {
              inherit (config.mx) priority;
              value = config.mx.target;
            } else if config.out.type == "TXT" then {
              inherit (config.txt) value;
            } else throw "unknown DNS record ${config.out.type}");
          };
          dns = let
            name = config.domain;
            zone = config.out.zone.domain;
          in {
            provider = config.out.zone.provider.set;
            type = "${toLower config.out.type}_record"
              + optionalString (config.out.type != "CNAME" && config.out.type != "PTR") "_set";
            inputs = {
              A = {
                inherit zone;
                inherit (config) ttl;
                addresses = singleton config.a.address;
              } // optionalAttrs (name != null) {
                inherit name;
              };
              AAAA = {
                inherit zone;
                inherit (config) ttl;
                addresses = singleton config.aaaa.address;
              } // optionalAttrs (name != null) {
                inherit name;
              };
              MX = {
                inherit zone;
                inherit (config) ttl;
                mx = singleton {
                  preference = config.mx.priority;
                  exchange = config.mx.target;
                };
              };
              TXT = {
                inherit zone;
                inherit (config) ttl;
                txt = singleton config.txt.value;
              } // optionalAttrs (name != null) {
                inherit name;
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
    mapAttrs' (name: cfg: nameValuePair cfg.out.resourceName {
      inherit (cfg) enable dataSource;
      inherit (cfg.out.set) provider type;
      inputs = mkIf cfg.enable cfg.out.set.inputs;
    }) (filterAttrs (_: z: z.create) cfg.zones)
    // mapAttrs' (name: cfg: nameValuePair cfg.out.resourceName {
      inherit (cfg) enable;
      inherit (cfg.out.set) provider type;
      inputs = mkIf cfg.enable cfg.out.set.inputs;
    }) cfg.records;
}

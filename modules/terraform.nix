{ pkgs, config, lib, ... }: with lib; let
  tconfig = config;
  # TODO: filter out all empty/unnecessary/default keys and objects
  tf = import ../lib/lib.nix {
    inherit pkgs config lib;
  };
  pathType = types.str; # types.path except that ${} expressions work too (and also sometimes relative paths?)
  resourceType = types.submodule ({ config, name, ... }: {
    options = {
      name = mkOption {
        type = types.str;
        default = name;
      };
      enable = mkOption {
        type = types.bool;
        default = true;
      };
      dataSource = mkOption {
        type = types.bool;
        default = false;
      };
      provider = mkOption {
        type = types.str;
        example = "aws.alias";
        # TODO: support just "alias" since "config.providers" is an attrset so they must be unique anyway?
      };
      type = mkOption {
        type = types.str;
        example = "instance";
      };
      inputs = mkOption {
        type = types.attrsOf types.unspecified;
        default = { };
        example = {
          instance_type = "t2.micro";
        };
        description = ''
          The "default" alias will be used as a fallback if no alias is provided.
        '';
      };
      dependencies = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      count = mkOption {
        type = types.int;
        default = 1;
      };
      # TODO: for_each
      connection = mkOption {
        type = types.nullOr (connectionType config);
        default = null;
      };
      provisioners = mkOption {
        type = types.listOf provisionerType;
        default = [ ];
      };
      timeouts = mkOption {
        type = timeoutsType;
        default = { };
      };
      hcl = mkOption {
        type = types.attrsOf types.unspecified;
        readOnly = true;
      };
      out = {
        providerType = mkOption {
          type = types.str;
          internal = true;
        };
        provider = mkOption {
          type = types.unspecified;
          internal = true;
        };
        resourceKey = mkOption {
          type = types.str;
          internal = true;
        };
        dataType = mkOption {
          type = types.str;
          internal = true;
        };
        reference = mkOption {
          type = types.str;
          internal = true;
        };
        hclPath = mkOption {
          type = types.listOf types.str;
          internal = true;
        };
        hclPathStr = mkOption {
          type = types.str;
          internal = true;
        };
      };
      refAttr = mkOption {
        type = types.unspecified;
        internal = true;
      };
      getAttr = mkOption {
        type = types.unspecified;
      };
    };

    config = {
      out = {
        providerType = head (splitString "." config.provider);
        provider = let
          default = if config.provider != config.out.providerType
            then throw "provider ${config.provider} not found"
            else null;
        in findFirst (p: p.out.reference == config.provider) default (attrValues tconfig.providers);
        resourceKey = "${config.out.providerType}_${config.type}";
        dataType = if config.dataSource then "data" else "resource";
        reference = optionalString config.dataSource "data." + config.out.resourceKey + ".${config.name}";
        hclPath = [ config.out.dataType config.out.resourceKey config.name ];
        hclPathStr = concatStringsSep "." config.out.hclPath;
      };
      refAttr = attr: tf.terraformContext config.out.hclPathStr attr
        + tf.terraformExpr "${config.out.reference}${optionalString (attr != null) ".${attr}"}";
      hcl = config.inputs // optionalAttrs (config.count != 1) {
        inherit (config) count;
      } // optionalAttrs (config.provisioners != [ ]) {
        provisioner = map (p: p.hcl) config.provisioners;
      } // optionalAttrs (config.connection != null) {
        connection = config.connection.hcl;
      } // optionalAttrs (config.timeouts.hcl != { }) {
        timeouts = config.timeouts.hcl;
      } // optionalAttrs (config.out.provider != null) {
        provider = tf.terraformContext config.out.provider.out.hclPathStr null + config.provider;
      };
      getAttr = attr: let
        ctx = tf.terraformContext config.out.hclPathStr attr;
        exists = tconfig.state.resources ? ${config.out.reference};
      in mkOptionDefault (ctx + optionalString exists tconfig.state.resources.${config.out.reference});
    };
  });
  provisionerType = types.submodule ({ config, ... }: {
    options = {
      type = mkOption {
        type = types.str;
        example = "local-exec";
      };
      when = mkOption {
        type = types.enum [ "create" "destroy" ];
        default = "create";
      };
      onFailure = mkOption {
        type = types.enum [ "continue" "fail" ];
        default = "fail";
      };
      inputs = mkOption {
        type = types.attrsOf types.unspecified;
        example = {
          command = "echo The server's IP address is \${self.private_ip}";
        };
      };
      hcl = mkOption {
        type = types.attrsOf types.unspecified;
        readOnly = true;
      };

      # built-in provisioners
      local-exec = mkOption {
        type = types.nullOr (types.submodule ({ config, ... }: {
          options = {
            command = mkOption {
              type = types.lines;
            };
            hcl = mkOption {
              type = types.attrsOf types.unspecified;
              readOnly = true;
            };
          };

          config.hcl = {
            inherit (config) command;
          };
        }));
        default = null;
      };
      remote-exec = mkOption {
        type = types.nullOr (types.submodule ({ config, ... }: {
          options = {
            inline = mkOption {
              type = types.nullOr (types.listOf types.str);
              default = null;
            };
            scripts = mkOption {
              type = types.listOf pathType;
              default = [ ];
            };
            command = mkOption {
              type = types.lines;
              default = "";
              description = "Alias for inline";
            };
            hcl = mkOption {
              type = types.attrsOf types.unspecified;
              readOnly = true;
            };
          };

          config = {
            inline = mkIf (config.command != "") [ config.command ];

            hcl = optionalAttrs (config.inline != null) {
              inline = assert config.scripts == [ ]; config.inline;
            } // optionalAttrs (length config.scripts == 1) {
              script = assert config.inline == null; head config.scripts;
            } // optionalAttrs (length config.scripts > 1) {
              scripts = assert config.inline == null; config.scripts;
            };
          };
        }));
        default = null;
      };
      file = mkOption {
        type = types.nullOr (types.submodule ({ config, ... }: {
          options = {
            destination = mkOption {
              type = pathType;
            };
            source = mkOption {
              type = types.nullOr pathType;
              default = null;
            };
            content = mkOption {
              type = types.nullOr types.str;
              default = null;
            };
            hcl = mkOption {
              type = types.attrsOf types.unspecified;
              readOnly = true;
            };
          };
          config = {
            hcl = {
              inherit (config) destination;
            } // optionalAttrs (config.source != null) {
              source = assert config.content == null; config.source;
            } // optionalAttrs (config.content != null) {
              content = assert config.source == null; config.content;
            };
          };
        }));
        default = null;
      };
      # TODO: chef, habitat, puppet, salt-masterless (https://www.terraform.io/docs/provisioners/)
    };

    config = let
      attrs' = filterAttrs (_: v: v != null) {
        inherit (config) local-exec remote-exec file;
      };
      attrs = mapAttrsToList nameValuePair attrs';
      attr = head attrs;
    in {
      type = assert length attrs <= 1; mkIf (attrs != [ ]) attr.name;
      inputs = mkIf (attrs != [ ]) attr.value.hcl;
      hcl = {
        ${config.type} = optionalAttrs (config.when != "create") {
          inherit (config) when;
        } // optionalAttrs (config.onFailure != "fail") {
          on_failure = config.onFailure;
        } // config.inputs;
      };
    };
  });
  connectionType = self: types.submodule ({ config, ... }: {
    options = {
      hcl = mkOption {
        type = types.attrsOf types.unspecified;
        readOnly = true;
      };
      nixStoreUrl = mkOption {
        type = types.str;
        readOnly = true;
      };
      type = mkOption {
        type = types.enum [ "ssh" "winrm" ];
        default = "ssh";
      };
      user = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      timeout = mkOption {
        type = types.nullOr timeoutType;
        default = null;
      };
      scriptPath = mkOption {
        type = types.nullOr pathType;
        default = null;
      };
      host = mkOption {
        type = types.str;
      };
      # ssh options
      ssh = {
        privateKey = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        privateKeyFile = mkOption {
          type = types.nullOr types.str;
          default = null;
          # NOTE: this is not directly used by hcl
        };
        hostKey = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        certificate = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        agent = {
          enabled = mkOption {
            type = types.bool;
            default = true;
          };
          identity = mkOption {
            type = types.nullOr types.str;
            default = null;
          };
        };
        bastion = {
          host = mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          hostKey = mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          port = mkOption {
            type = types.nullOr types.port;
            default = null;
          };
          user = mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          password = mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          privateKey = mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          certificate = mkOption {
            type = types.nullOr types.str;
            default = null;
          };
        };
      };
      winrm = {
        https = mkOption {
          type = types.bool;
          default = false;
        };
        insecure = mkOption {
          type = types.bool;
          default = false;
        };
        useNtlm = mkOption {
          type = types.bool;
          default = false;
        };
        cacert = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
      };
      set = mkOption {
        type = types.attrsOf types.unspecified;
        readOnly = true;
      };
    };

    config = {
      hcl = filterAttrs (_: v: v != null) {
        inherit (config) type user timeout host;
        script_path = config.scriptPath;
        private_key = config.ssh.privateKey;
        host_key = config.ssh.hostKey;
        inherit (config.ssh) certificate;
        agent = config.ssh.agent.enabled;
        agent_identity = config.ssh.agent.identity;

        bastion_host = config.ssh.bastion.host;
        bastion_host_key = config.ssh.bastion.hostKey;
        bastion_port = config.ssh.bastion.port;
        bastion_user = config.ssh.bastion.user;
        bastion_password = config.ssh.bastion.password;
        bastion_private_key = config.ssh.bastion.privateKey;
        bastion_certificate = config.ssh.bastion.certificate;

        inherit (config.winrm) https insecure cacert;
        use_ntlm = config.winrm.useNtlm;
      };
      set = let
        attrs = {
          inherit (config) ssh winrm type user timeout scriptPath host;
        };
        attrs' = filterAttrs (_: v: v != null) attrs;
        selfRef = tf.terraformContext self.out.hclPathStr null + "\${${self.out.reference}.";
        mapSelf = v: if isString v then replaceStrings [ "\${self." ] [ selfRef ] v else v;
      in mapAttrs (_: mapSelf) attrs';
      nixStoreUrl = let
        user = if config.user == null then "root" else config.user;
        sshKey = optionalString (config.ssh.privateKeyFile != null) "?ssh-key=${config.ssh.privateKeyFile}";
      in "ssh://${user}@${config.host}${sshKey}";
    };
  });
  providerType = types.submodule ({ name, config, ... }: {
    options = {
      type = mkOption {
        type = types.str;
        default = name;
      };
      alias = mkOption {
        type = types.nullOr types.str;
        default = if name == config.type then null else name;
      };
      inputs = mkOption {
        type = types.attrsOf types.unspecified;
        default = { };
      };
      hcl = mkOption {
        type = types.attrsOf types.unspecified;
        readOnly = true;
      };
      out = {
        reference = mkOption {
          type = types.str;
          readOnly = true;
        };
        hclPath = mkOption {
          type = types.listOf types.str;
          internal = true;
        };
        hclPathStr = mkOption {
          type = types.str;
          internal = true;
        };
      };
    };

    config = {
      hcl = config.inputs // optionalAttrs (config.alias != null) {
        inherit (config) alias;
      };
      out = {
        reference = "${config.type}${optionalString (config.alias != null) ".${config.alias}"}";
        hclPath = [ "provider" config.type ] ++ optional (config.alias != null) config.alias;
        hclPathStr = concatStringsSep "." config.out.hclPath;
      };
    };
  });
  variableType = types.submodule ({ name, config, ... }: {
    options = {
      type = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      default = mkOption {
        type = types.nullOr types.unspecified;
        default = null;
      };
      name = mkOption {
        type = types.str;
        default = name;
      };
      hcl = mkOption {
        type = types.attrsOf types.unspecified;
        readOnly = true;
      };
      out = {
        reference = mkOption {
          type = types.str;
          readOnly = true;
        };
        hclPath = mkOption {
          type = types.listOf types.str;
          internal = true;
        };
        hclPathStr = mkOption {
          type = types.str;
          internal = true;
        };
      };
      ref = mkOption {
        type = types.str;
        readOnly = true;
      };
    };

    config = {
      hcl = filterAttrs (_: v: v != null) {
        inherit (config) type default;
      };
      out = {
        reference = "var.${config.name}";
        hclPath = [ "variable" config.name ];
        hclPathStr = concatStringsSep "." config.out.hclPath;
      };
      ref = tf.terraformContext config.out.hclPathStr null
        + tf.terraformExpr config.out.reference;
    };
  });
  outputType = types.submodule ({ name, config, ... }: {
    options = {
      type = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      description = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      sensitive = mkOption {
        type = types.bool;
        default = false;
      };
      dependsOn = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      value = mkOption {
        type = types.str;
      };
      name = mkOption {
        type = types.str;
        default = name;
      };
      hcl = mkOption {
        type = types.attrsOf types.unspecified;
        readOnly = true;
      };
      out = {
        reference = mkOption {
          type = types.str;
          readOnly = true;
        };
        hclPath = mkOption {
          type = types.listOf types.str;
          internal = true;
        };
        hclPathStr = mkOption {
          type = types.str;
          internal = true;
        };
      };
      get = mkOption {
        type = types.str;
      };
    };

    config = {
      hcl = {
        inherit (config) value;
      } // filterAttrs (_: v: v != null) {
        inherit (config) type description;
      } // optionalAttrs config.sensitive {
        sensitive = true;
      } // optionalAttrs (config.dependsOn != [ ]) {
        depends_on = config.dependsOn;
      };
      out = {
        reference = "output.${config.name}";
        hclPath = [ "output" config.name ];
        hclPathStr = concatStringsSep "." config.out.hclPath;
      };
      get = let
        ctx = tf.terraformContext config.out.hclPathStr null;
        exists = tconfig.state.outputs ? ${config.name};
      in mkOptionDefault (ctx + optionalString exists tconfig.state.outputs.${config.name});
    };
  });
  moduleType = types.submodule ({ name, config, ... }: {
    options = {
      name = mkOption {
        type = types.str;
        default = name;
      };
      source = mkOption {
        type = types.str;
      };
      version = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      providers = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
      inputs = mkOption {
        type = types.attrsOf types.unspecified;
        default = { };
      };
      # TODO: count, for_each, lifecycle
      hcl = mkOption {
        type = types.attrsOf types.unspecified;
        readOnly = true;
      };
      out = {
        reference = mkOption {
          type = types.str;
          readOnly = true;
        };
        hclPath = mkOption {
          type = types.listOf types.str;
          internal = true;
        };
        hclPathStr = mkOption {
          type = types.str;
          internal = true;
        };
      };
    };

    config = {
      hcl = filterAttrs (_: v: v != null) {
        inherit (config) source version;
      } // optionalAttrs (config.providers != { }) {
        inherit (config) providers;
      } // config.inputs;
      out = {
        reference = "module.${config.name}";
        hclPath = [ "module" config.name ];
        hclPathStr = concatStringsSep "." config.out.hclPath;
      };
    };
  });
  timeoutType = types.str; # TODO: validate "2h" "60m" "10s" etc
  timeoutsType = types.submodule ({ config, ... }: {
    # NOTE: only a limited subset of resource types support this? why not just put it in inputs?
    options = {
      create = mkOption {
        type = types.nullOr timeoutType;
        default = null;
      };
      delete = mkOption {
        type = types.nullOr timeoutType;
        default = null;
      };
      update = mkOption {
        type = types.nullOr timeoutType;
        default = null;
      };
      hcl = mkOption {
        type = types.attrsOf types.unspecified;
        readOnly = true;
      };
    };

    config.hcl = filterAttrs (_: v: v != null) {
      inherit (config) create delete update;
    };
  });
  stateType = types.submodule ({ config, ... }: {
    options = {
      outputs = mkOption {
        type = types.attrsOf types.unspecified;
        default = { };
      };
      resources = mkOption {
        type = types.attrsOf types.unspecified;
        default = { };
      };
    };
  });
in {
  options = {
    resources = mkOption {
      type = types.attrsOf resourceType;
      default = { };
    };
    providers = mkOption {
      type = types.attrsOf providerType;
      default = { };
    };
    variables = mkOption {
      type = types.attrsOf variableType;
      default = { };
    };
    outputs = mkOption {
      type = types.attrsOf outputType;
      default = { };
    };
    modules = mkOption {
      type = types.attrsOf moduleType;
      default = { };
    };

    state = mkOption {
      type = types.attrsOf stateType;
      default = { };
    };

    terraform = {
      version = mkOption {
        type = types.enum [ "0.11" "0.12" ];
        default = "0.12";
      };
      googleBeta = mkOption {
        type = types.bool;
        default = false;
      };
      package = mkOption {
        type = types.package;
        readOnly = true;
      };
      wrapper = mkOption {
        type = types.unspecified;
        default = terraform: pkgs.callPackage ../lib/wrapper.nix { inherit terraform; };
      };
      providers = mkOption {
        type = types.listOf types.str;
      };
    };

    hcl = mkOption {
      type = types.attrsOf types.unspecified;
      readOnly = true;
    };

    lib = mkOption {
      type = types.attrsOf (types.attrsOf types.unspecified);
      default = { };
    };
  };

  config = {
    terraform = {
      package = let
        tf = {
          "0.11" = pkgs.terraform_0_11;
          "0.12" = pkgs.terraform_0_12;
        }.${config.terraform.version};
        translateProvider = provider: (optionalAttrs config.terraform.googleBeta {
          google = "google-beta";
        }).${provider} or provider;
        mapProvider = p: provider: p.${translateProvider provider};
        terraform = tf.withPlugins (ps: map (mapProvider ps) config.terraform.providers);
      in config.terraform.wrapper terraform;
      providers = unique (
        mapAttrsToList (_: p: p.type) config.providers
        ++ mapAttrsToList (_: r: r.out.providerType) config.resources
      );
    };
    hcl = {
      resource = let
        resources' = filter (r: !r.dataSource && r.enable) (attrValues config.resources);
        resources = groupBy (r: r.out.resourceKey) resources';
      in mkIf (resources != { }) (mapAttrs (_: r: listToAttrs (map (r: nameValuePair r.name r.hcl) r)) resources);
      data = let
        resources' = filter (r: r.dataSource && r.enable) (attrValues config.resources);
        resources = groupBy (r: r.out.resourceKey) resources';
      in mkIf (resources != { }) (mapAttrs (_: r: listToAttrs (map (r: nameValuePair r.name r.hcl) r)) resources);
      provider = let
        providers' = attrValues config.providers;
        providers = filter (p: p.hcl != { }) providers';
      in mkIf (providers != [ ]) (map (p: { ${p.type} = p.hcl; }) providers);
      output = mkIf (config.outputs != { }) (mapAttrs' (_: o: nameValuePair o.name o.hcl) config.outputs);
      variables = mkIf (config.variables != { }) (mapAttrs' (_: o: nameValuePair o.name o.hcl) config.variables);
    };
    lib = {
      inherit tf;
    };
  };
}

{ pkgs, config, lib, ... }: with lib; let
  tconfig = config;
  # TODO: filter out all empty/unnecessary/default keys and objects
  tf = import ../lib/lib.nix {
    inherit pkgs config lib;
  } // {
    tfTypes = {
      inherit pathType providerReferenceType providerType resourceType outputType moduleType variableType
        connectionType provisionerType;
    };
  };
  pathType = types.str; # types.path except that ${} expressions work too (and also sometimes relative paths?)
  providerReferenceType' = types.submodule ({ config, ... }: let
    split = splitString "." config.reference;
  in {
    options = {
      # TODO: support just "alias" since "config.providers" is an attrset so they must be unique anyway?
      type = mkOption {
        type = types.str;
        default = head split;
      };
      alias = mkOption {
        type = types.nullOr types.str;
        default = if tail split == [ ] then null else elemAt split 1;
      };
      reference = mkOption {
        type = types.nullOr types.str;
        default = "${config.type}${optionalString (config.alias != null) ".${config.alias}"}";
      };
      isDefault = mkOption {
        type = types.bool;
        default = config.alias == null;
        readOnly = true;
      };
      out = {
        name = mkOption {
          type = types.str;
          readOnly = true;
        };
        provider = mkOption {
          type = types.unspecified;
          readOnly = true;
        };
      };
      ref = mkOption {
        type = types.str;
        readOnly = true;
      };
      set = mkOption {
        type = types.attrsOf types.unspecified;
        readOnly = true;
      };
    };
    config = {
      out = {
        name = if config.alias != null then config.alias else config.type;
        provider = let
          default = if !config.isDefault
            then throw "provider ${config.reference} not found"
            else null;
        in findFirst (p: p.out.reference == config.reference) default (attrValues tconfig.providers);
      };
      ref =
        optionalString (config.out.provider != null) (tf.terraformContext false config.out.provider.out.hclPathStr null)
        + config.reference;
      set = {
        inherit (config) type alias reference;
      };
    };
  });
  providerReferenceType = types.coercedTo types.str (reference: { inherit reference; }) providerReferenceType';
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
        type = providerReferenceType;
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
      dependsOn = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      count = mkOption {
        type = types.int;
        default = 1;
      };
      # TODO: for_each
      lifecycle = {
        createBeforeDestroy = mkOption {
          type = types.bool;
          default = false;
        };
        ignoreChanges = mkOption {
          type = types.either (types.enum [ "all" ]) (types.listOf types.str);
          default = [ ];
        };
        preventDestroy = mkOption {
          type = types.bool;
          default = false;
        };
      };
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
      importAttr = mkOption {
        type = types.unspecified;
      };
      refAttr = mkOption {
        type = types.unspecified;
        internal = true;
      };
      getAttr = mkOption {
        type = types.unspecified;
      };
      namedRef = mkOption {
        type = types.unspecified;
        internal = true;
      };
    };

    config = {
      out = {
        resourceKey = "${config.provider.type}_${config.type}";
        dataType = if config.dataSource then "data" else "resource";
        reference = optionalString config.dataSource "data." + config.out.resourceKey + ".${config.name}";
        hclPath = [ config.out.dataType config.out.resourceKey config.name ];
        hclPathStr = concatStringsSep "." config.out.hclPath;
      };
      refAttr = attr: tf.terraformContext false config.out.hclPathStr attr
        + tf.terraformExpr "${config.out.reference}${optionalString (attr != null) ".${attr}"}";
      hcl = config.inputs // optionalAttrs (config.count != 1) {
        inherit (config) count;
      } // optionalAttrs (config.provisioners != [ ]) {
        provisioner = map (p: p.hcl) config.provisioners;
      } // optionalAttrs (config.dependsOn != [ ]) {
        depends_on = config.dependsOn;
      } // optionalAttrs (config.connection != null) {
        connection = config.connection.hcl;
      } // optionalAttrs (config.timeouts.hcl != { }) {
        timeouts = config.timeouts.hcl;
      } // optionalAttrs (!config.provider.isDefault || config.provider.out.provider != null) {
        provider = config.provider.ref;
      } // optionalAttrs (config.lifecycle.createBeforeDestroy || config.lifecycle.preventDestroy || config.lifecycle.ignoreChanges != [ ]) {
        lifecycle = optionalAttrs (config.lifecycle.createBeforeDestroy) {
          create_before_destroy = true;
        } // optionalAttrs (config.lifecycle.preventDestroy) {
          prevent_destroy = true;
        } // optionalAttrs (config.lifecycle.ignoreChanges != [ ]) {
          ignore_changes = config.lifecycle.ignoreChanges;
        };
      };
      getAttr = mkOptionDefault (attr: let
        ctx = tf.terraformContext exists config.out.hclPathStr attr;
        exists = tconfig.state.resources ? ${config.out.reference};
      in (ctx + optionalString exists tconfig.state.resources.${config.out.reference}.${attr}));
      importAttr = mkOptionDefault (attr: let
        ctx = tf.terraformContext exists config.out.hclPathStr attr;
        exists = tconfig.state.resources ? ${config.out.reference};
      in if exists then tconfig.state.resources.${config.out.reference}.${attr} else throw "imported resource ${config.out.reference} not found");
      namedRef = tf.terraformContext false config.out.hclPathStr null
        + config.out.reference;
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
            working_dir = mkOption {
              type = types.nullOr types.path;
              default = null;
            };
            environment = mkOption {
              type = types.attrsOf types.str;
              default = { };
            };
            interpreter = mkOption {
              type = types.listOf types.str;
              default = [ ];
            };
            hcl = mkOption {
              type = types.attrsOf types.unspecified;
              readOnly = true;
            };
          };

          config.hcl = {
            inherit (config) command;
          } // optionalAttrs (config.working_dir != null) {
            inherit (config) working_dir;
          } // optionalAttrs (config.environment != { }) {
            inherit (config) environment;
          } // optionalAttrs (config.interpreter != [ ]) {
            inherit (config) interpreter;
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
      port = mkOption {
        type = types.nullOr types.port;
        default = null;
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
      out = {
        ssh = {
          opts = mkOption {
            type = types.attrsOf types.str;
            readOnly = true;
          };
          nixStoreOpts = mkOption {
            type = types.str;
            readOnly = true;
            description = "NIX_SSHOPTS";
          };
          cliArgs = mkOption {
            type = types.listOf types.str;
            readOnly = true;
          };
          destination = mkOption {
            type = types.str;
            readOnly = true;
          };
        };
      };
    };

    config = {
      hcl = filterAttrs (_: v: v != null) {
        inherit (config) type user timeout host port;
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
          inherit (config) ssh winrm type user timeout scriptPath host port;
        };
        attrs' = filterAttrs (_: v: v != null) attrs;
        selfRef = tf.terraformContext false self.out.hclPathStr null + "\${${self.out.reference}.";
        selfPrefix = "\${self.";
        mapSelf = v: if isString v && hasInfix selfPrefix v then replaceStrings [ selfPrefix ] [ selfRef ] v else v;
      in mapAttrsRecursive (_: mapSelf) attrs';
      nixStoreUrl = let
        sshKey = optionalString (config.ssh.privateKeyFile != null) "?ssh-key=${config.ssh.privateKeyFile}";
        # Waiting on fix for: https://github.com/NixOS/nix/issues/1994
        port = optionalString (/*config.port != null*/false) ":${toString config.port}";
      in "ssh://${config.out.ssh.destination}${port}${sshKey}";
      out.ssh = let
        bastionDestination =
          optionalString (config.ssh.bastion.user != null) "${config.ssh.bastion.user}@"
          + config.ssh.bastion.host
          + optionalString (config.ssh.bastion.port != null) ":${toString config.ssh.bastion.port}";
      in {
        nixStoreOpts = concatStringsSep " " config.out.ssh.cliArgs;
        opts = {
          UpdateHostKeys = "no";
          User = if config.user == null then "root" else config.user;
          # TODO: cert and hostkey
        } // optionalAttrs (config.ssh.bastion.host != null) {
          ProxyJump = bastionDestination;
        } // optionalAttrs (config.port != null) {
          Port = toString config.port;
        } // optionalAttrs (config.ssh.privateKeyFile != null) {
          IdentityFile = config.ssh.privateKeyFile;
        };
        cliArgs =
          [ "-q" "-o" "UpdateHostKeys=no" ]
          ++ optionals (config.ssh.bastion.host != null) [ "-J" bastionDestination ]
          ++ optionals (config.port != null) [ "-p" (toString config.port) ]
          ++ optionals (config.ssh.privateKeyFile != null) [ "-i" config.ssh.privateKeyFile ];
        destination = "${if config.user == null then "root" else config.user}@${config.host}";
      };
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
      source = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      version = mkOption {
        type = types.nullOr types.str;
        default = null;
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
  requiredProviderType = types.submodule ({ name, config, ... }: {
    options = {
      type = mkOption {
        type = types.str;
        default = name;
        readOnly = true;
      };
      source = mkOption {
        type = types.nullOr types.str;
        default =
          if versionAtLeast tconfig.terraform.version "0.13" && tconfig.terraform.packageUnwrapped ? plugins.${config.type}.provider-source-address
          then tconfig.terraform.packageUnwrapped.plugins.${config.type}.provider-source-address
          else "nixpkgs/${config.type}";
      };
      version = mkOption {
        type = types.nullOr types.str;
        default =
          if versionAtLeast tconfig.terraform.version "0.13" && tconfig.terraform.packageUnwrapped ? plugins.${config.type}.version
          then tconfig.terraform.packageUnwrapped.plugins.${config.type}.version
          else null;
      };
      hcl = mkOption {
        type = types.attrsOf types.unspecified;
        readOnly = true;
      };
    };
    config = {
      hcl = {
        source = mkIf (config.source != null) config.source;
        version = mkIf (config.version != null) config.version;
      };
    };
  });
  variableValidationType = types.submodule ({ config, ... }: {
    options = {
      condition = mkOption {
        type = types.str;
      };
      errorMessage = mkOption {
        type = types.str;
      };
      hcl = mkOption {
        type = types.attrsOf types.unspecified;
        readOnly = true;
      };
    };
    config = {
      hcl = {
        inherit (config) condition;
        error_message = config.errorMessage;
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
      validation = mkOption {
        # new in 0.13
        type = types.nullOr variableValidationType;
        default = null;
      };
      value = {
        shellCommand = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
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
        validation = mapNullable (v: v.hcl) config.validation;
      };
      out = {
        reference = "var.${config.name}";
        hclPath = [ "variable" config.name ];
        hclPathStr = concatStringsSep "." config.out.hclPath;
      };
      ref = tf.terraformContext false config.out.hclPathStr null
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
        type = types.unspecified;
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
        type = types.unspecified;
        readOnly = true;
      };
      import = mkOption {
        type = types.unspecified;
        readOnly = true;
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
        ctx = tf.terraformContext exists config.out.hclPathStr null;
        exists = tconfig.state.outputs ? ${config.out.reference};
      in mkOptionDefault (ctx + optionalString exists tconfig.state.outputs.${config.out.reference});
      import = mkOptionDefault (let
        ctx = tf.terraformContext exists config.out.hclPathStr null;
        exists = tconfig.state.outputs ? ${config.out.reference};
      in if exists then tconfig.state.outputs.${config.out.reference} else throw "imported output ${config.out.reference} not found");
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

    state = {
      outputs = mkOption {
        type = types.attrsOf types.unspecified;
        default = { };
      };
      resources = mkOption {
        type = types.attrsOf types.unspecified;
        default = { };
      };
    };

    terraform = {
      version = mkOption {
        type = types.enum [ "0.11" "0.12" "0.13" "0.14" "0.15" "1.0" ];
        default = if pkgs ? terraform_1_0 then "1.0" else "0.13";
      };
      package = mkOption {
        type = types.package;
        readOnly = true;
      };
      packageUnwrapped = mkOption {
        type = types.package;
        readOnly = true;
      };
      packageWithPlugins = mkOption {
        type = types.package;
        readOnly = true;
      };
      cli = mkOption {
        type = types.package;
        readOnly = true;
      };
      wrapper = mkOption {
        type = types.unspecified;
        default = terraform: pkgs.callPackage ../lib/wrapper.nix { inherit terraform; };
      };
      requiredProviders = mkOption {
        type = types.attrsOf requiredProviderType;
        default = { };
      };
      refreshOnApply = mkOption {
        type = types.bool;
        default = true;
      };
      autoApprove = mkOption {
        type = types.bool;
        default = false;
      };
      logLevel = mkOption {
        type = types.enum [ "TRACE" "DEBUG" "INFO" "WARN" "ERROR" "" ];
        default = "";
      };
      logPath = mkOption {
        type = types.nullOr types.path;
        default = null;
      };
      dataDir = mkOption {
        type = types.nullOr types.path;
        default = null;
      };
      environment = mkOption {
        type = types.attrsOf (types.separatedString " ");
        default = { };
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
      packageUnwrapped = {
        "0.11" = pkgs.terraform_0_11;
        "0.12" = pkgs.terraform_0_12;
        "0.13" = pkgs.terraform_0_13;
        "0.14" = pkgs.terraform_0_14;
        "0.15" = pkgs.terraform_0_15;
        "1.0" = pkgs.terraform_1_0;
      }.${config.terraform.version};
      package = config.terraform.wrapper config.terraform.packageWithPlugins;
      packageWithPlugins = let
        pluginFor = ps: p:
          if ps ? ${p.type} then ps.${p.type} else throw "terraform provider plugin ${p.type} not found";
      in config.terraform.packageUnwrapped.withPlugins (ps:
        mapAttrsToList (_: pluginFor ps) config.terraform.requiredProviders
      );
      requiredProviders = mkMerge (
        mapAttrsToList (_: p: {
          ${p.type} = mapAttrs (_: mkDefault) (filterAttrs (_: v: v != null) {
            inherit (p) source version;
          });
        }) config.providers
        ++ mapAttrsToList (_: r: { ${r.provider.type} = { }; }) config.resources
      );
      cli = let
        vars = config.terraform.environment;
      in pkgs.writeShellScriptBin "terraform" ''
        set -eu
        exec env ${concatStringsSep " " (mapAttrsToList (k: v:
        ''"${k}=${v}"''
        ) vars)} \
        ${config.terraform.package}/bin/terraform "$@"
      '';
      environment =
        mapAttrs' (_: var:
          nameValuePair "TF_VAR_${var.name}" (mkOptionDefault "$(${var.value.shellCommand})")
        ) (filterAttrs (_: var: var.value.shellCommand != null) config.variables) // {
          TF_CONFIG_DIR = mkOptionDefault "${tf.hclDir {
            inherit (config) hcl;
            terraform = config.terraform.packageWithPlugins;
          }}";
          TF_LOG_PATH = mkIf (config.terraform.logPath != null) (mkOptionDefault (toString config.terraform.logPath));
          TF_DATA_DIR = mkIf (config.terraform.dataDir != null) (mkOptionDefault (toString config.terraform.dataDir));
          TF_STATE_FILE = mkIf (config.state.file != null) (mkOptionDefault (toString config.state.file));
          TF_CLI_CONFIG_FILE = mkOptionDefault "${pkgs.writeText "terraformrc" ''
            disable_checkpoint = true
          ''}";
          TF_CLI_ARGS_init = mkIf (versionAtLeast config.terraform.version "0.14") "-lockfile=readonly";
          TF_CLI_ARGS_refresh = "-compact-warnings";
          TF_CLI_ARGS_state_replace_provider = "-auto-approve";
          TF_CLI_ARGS_apply = mkMerge ([
            "-compact-warnings"
            "-refresh=${if config.terraform.refreshOnApply then "true" else "false"}"
          ] ++ optional config.terraform.autoApprove "-auto-approve");
          TF_IN_AUTOMATION = mkOptionDefault "1";
          TF_LOG = mkOptionDefault config.terraform.logLevel;
        };
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
      terraform = let
        providers = config.terraform.requiredProviders;
        v0_13 = mapAttrs' (_: p: nameValuePair p.type p.hcl) providers;
        v0_12 = mapAttrs' (_: p: nameValuePair p.type p.version) providers;
        required_providers' = if versionAtLeast config.terraform.version "0.13" then v0_13 else v0_12;
        required_providers = filterAttrs (_: p: p != { } && p != null) required_providers';
      in optionalAttrs (required_providers != { }) {
        inherit required_providers;
      };
    };
    runners.run = {
      terraform.package = config.terraform.cli;
    };
    lib = {
      inherit tf;
    };
  };
}

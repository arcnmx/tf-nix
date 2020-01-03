{ pkgs ? import <nixpkgs> { }, config ? ./example/example.nix, terraformState ? null, terraformTargets ? [] }: with pkgs.lib; let
  storeDirRe = replaceStrings [ "." ] [ "\\." ] builtins.storeDir;
  storeBaseRe = "[0-9a-df-np-sv-z]{32}-[+_?=a-zA-Z0-9-][+_?=.a-zA-Z0-9-]*";
  re = "(${storeDirRe}/${storeBaseRe}\\.drv)";
  inputDrvs = pkg: let
    # https://github.com/NixOS/nix/issues/1245#issuecomment-401642781
    drv = builtins.readFile pkg;
    inputs = concatLists (filter isList (builtins.split re drv));
  in inputs;
  inputDrvsRecursive = list: drvs:
    foldl (list: drv: if elem drv list then list else inputDrvsRecursive (list ++ singleton drv) (inputDrvs drv)) list drvs;
  tfPrefix = "tf-1terraformReference-";
  tfMatch = builtins.match ".*-${tfPrefix}(.*)\\.drv";
  terraformReferences = target:
    if isString target && hasSuffix ".drv" target then terraformReferencesDrv target
    else if ! isString target then terraformReferencesDrv target.drvPath
    else terraformReferencesString target;
  terraformReferencesString = str: let
    drvs = attrNames (builtins.getContext str);
  in unique (concatMap (s: let
    matches = tfMatch s;
  in if matches == null then [] else matches) drvs);
  terraformReferencesDrv = pkg: let
    closure = inputDrvsRecursive [] [ pkg ];
    isTerraformContext = drv: let
      d = builtins.parseDrvName (builtins.unsafeDiscardStringContext drv);
    in hasPrefix "1terraformReference-" d.version;
  in unique (concatMap (s: let
    matches = tfMatch s;
  in if matches == null then [] else matches) closure);
  terraformExpr = expr: "\${${expr}}";
  terraformContext = path: attr: let
    contextDrv = derivation {
      inherit (pkgs) system;
      name = "${tfPrefix}${path}";
      builder = "unresolved terraform reference";
      __terraformPath = path;
    };
  in addContextFrom "${contextDrv}" "";
  terraformProvider = config: provider: alias: let
    alias' = if alias == null then "default" else alias;
    # TODO: generate nothing in the json if alias' == "default"
    out = terraformContext "provider.${provider}.${alias'}" null + provider + optionalString (alias' != "default") ".${alias}";
  in if hasAttrByPath (splitString "." "terraform.provider.${provider}.${alias'}") config
    then out
    else throw "terraform provider.${provider}.${alias'} not found";
  terraformInput = config: name:
    if hasAttrByPath (splitString "." "terraform.variable.${name}") config # TODO: if any outputs exist but not the requested one, error!
      then terraformContext "variable.${name}" null + terraformExpr "var.${name}"
      else throw "terraform.variable.${name} not found";
  terraformOutput = config: path: attr: let
    expr = removePrefix "resource." path;
  in if hasAttrByPath (splitString "." "terraform.${path}") config # TODO: if any outputs exist but not the requested one, error!
    then terraformContext path attr
      + terraformExpr "${expr}${optionalString (attr != null) ".${attr}"}"
    else throw "terraform.${path} not found";
  terraformReference = config: path: attr: let
    path' = splitString "." "terraform.state.outputs.${tfOutputName path}.${attr}";
  in if hasAttrByPath path' config # TODO: if any outputs exist but not the requested one, error!
    then attrByPath path' null config
    else terraformContext "output.${tfOutputName path}" attr + terraformContext path attr;
  terraformJson = config: path: let
    target = attrByPath (splitString "." "terraform.${path}") null config;
  in builtins.toJSON target;
  terraformConnectionDetails = config: {
    type ? null # ssh, winrm
  , user ? null # root
  , timeout ? null # 5m
  , script_path ? null
  , resource ? null
  , attr ? "ipv4_address"
  , host ? terraformOutput config resource attr
  # ssh options
  , private_key ? null
  , certificate ? null
  , agent ? null # true
  , agent_identity ? null
  , host_key ? null
  # ssh bastion
  , bastion_host ? null
  , bastion_host_key ? null
  , bastion_port ? null
  , bastion_user ? null
  , bastion_password ? null
  , bastion_private_key ? null
  , bastion_certificate ? null
  # winrm options
  , https ? null # false
  , insecure ? null # false
  , use_ntlm ? null # false
  , cacert ? null
  }@args: {
    inherit host;
  } // removeAttrs args [ "host" "attr" "resource" ];
  terraformNixStoreUrl = config: {
    user ? "root"
  , attr ? "ipv4_address"
  , host ? terraformOutput config resource attr
  , resource ? null
  , path ? ""
  , private_key_file
  }: let
  in "ssh://${user}@${host}${path}?ssh-key=${private_key_file}";
  terraformSecret = config: name: let
  in throw "ugh secret ${name}";
  dag = import (builtins.fetchurl {
    url = "https://raw.githubusercontent.com/rycee/home-manager/master/modules/lib/dag.nix";
  }) { inherit (pkgs) lib; };
  terraformModule = { config, ... }: {
    imports = [ ./terranix/core/terraform-options.nix ];

    options = optionalAttrs (terraformState != null) {
      state.outputs = mkOption {
        type = types.attrsOf types.attrs;
        default = let
          stateData = builtins.readFile terraformState;
          state = mapAttrs (_: v: v.value) (builtins.fromJSON stateData).outputs;
          terraformTargets' = if isString terraformTargets then splitString "," terraformTargets else terraformTargets;
          terraformTargets'' = map tfOutputName terraformTargets';
        in filterAttrs (k: v: builtins.elem k terraformTargets'') state;
      };
    };

    config.output = listToAttrs (concatLists (mapAttrsToList (k0: v: mapAttrsToList (k1: v: nameValuePair (tfOutputName "resource.${k0}.${k1}") {
      value = terraformExpr "${k0}.${k1}";
    }) v) config.resource)) //
    listToAttrs (concatLists (mapAttrsToList (k0: v: mapAttrsToList (k1: v: nameValuePair (tfOutputName "data.${k0}.${k1}") {
      value = terraformExpr "data.${k0}.${k1}";
    }) v) config.data));
  };
  tfOutputName = replaceStrings [ "." ] [ "-" ];
  metaModule = { config, ... }: {
    options = {
      terraform = mkOption {
        type = types.submodule terraformModule;
        default = { };
      };
      terranix = {
        gcroots = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
        targets = mkOption {
          type = types.attrsOf (types.listOf types.str);
          default = { };
        };
      };
      nixos = mkOption {
        type = types.submodule ({ ... }: {
          imports = import (pkgs.path + "/nixos/modules/module-list.nix");
        });
        default = { };
      };
    };
    config = {
      nixos = {
        nixpkgs.system = pkgs.system;
        lib.terranix = {
          inherit terraformExpr terraformContext terraformReferences;
          terraformOutput = terraformOutput config;
          terraformProvider = terraformProvider config;
          terraformReference = terraformReference config;
          terraformConnectionDetails = terraformConnectionDetails config;
          terraformNixStoreUrl = terraformNixStoreUrl config;
          terraformSecret = terraformSecret config;
          terraformInput = terraformInput config;
          terraformJson = terraformJson config;
        };
        lib.dag = dag;
      };
      _module.args.pkgs = pkgs;
    };
  };
  tfConfigDir = {
    data
  , targets
  , terraform
  , args ? {}
  , env ? {}
  }: let
    targetArgs = map (target: "-target=${removePrefix "resource." target}") targets;
    args' = args // {
      plan = toString targetArgs;
      apply = toString targetArgs;
      destroy = toString targetArgs;
    };
    tfRest = builtins.fromJSON (builtins.unsafeDiscardStringContext (builtins.toJSON data.rest));
    tfData = removeTerraformContext (builtins.toJSON (recursiveUpdate tfRest data.data));
    env' = env // mapAttrs' (k: v: nameValuePair "TF_CLI_ARGS_${k}"
      "${toString v} $TF_CLI_ARGS_${k}"
    ) (filterAttrs (_: v: v != "") args');
  in pkgs.runCommand "terraform.tf" {
    passAsFile = [ "tfData" "script" ];
    inherit tfData;
    script = "#!${pkgs.runtimeShell}\n"
    + concatStringsSep "\n" (mapAttrsToList (k: v:
      ''export ${k}="${v}"''
    ) env') + "\n" + ''
      case ''${1-} in
        plan|apply|destroy|providers|graph|refresh)
          set -- "$@" @out@/share/tf
          ;;
      esac
      exec ${terraform}/bin/terraform "$@"
    '';
  } ''
    mkdir -p $out/bin $out/share/tf
    install -Dm0644 $tfDataPath $out/share/tf/terraform.tf.json
    substituteAll $scriptPath $out/bin/terraform
    chmod 0755 $out/bin/terraform
  '';
  commonEnv = {
    TF_CLI_CONFIG_FILE = builtins.toFile "terraformrc" ''
      disable_checkpoint = true
    '';
    TF_INPUT = 0;
    TF_IN_AUTOMATION = 1;
    #TF_LOG = "INFO";
  };
  removeTerraformContext = str: let
    context = builtins.getContext str;
    context' = filterAttrs (k: value: tfMatch k == null) context;
  in addContext context' str;
  addContext = context: str: let
    str' = builtins.unsafeDiscardStringContext str;
  in foldl (str: cx: addContextFrom "${import cx}" str) str' (attrNames context); # TODO: preserve context'.value.outputs
  config' = config;
in rec {
  config = (evalModules {
    modules = [ config' metaModule ];
    specialArgs = {
      modulesPath = toString (pkgs.path + "/nixos/modules");
    };
  }).config;
  #references = terraformReferences example.config.nixos.system.build.toplevel;
  #references = inputDrvsRecursive [] [ example.config.nixos.system.build.toplevel.drvPath ];
  targets = mapAttrs (k: v: with dag; let
    #path = splitString "." "${v}";
    #target = attrByPath path example.config.terraform;
    #referencesFor = path: terraformReferencesString (example.config.nixos.lib.terranix.terraformJson path);
    #after = referencesFor v;
    dagsFor = paths: foldl (a: b: a // dagFor b) {} paths;
    dagFor = path: let
      isTerraform = isString path && ! hasSuffix ".drv" path;
      json = config.nixos.lib.terranix.terraformJson path;
      nonTfReferences = let
        drvs = attrNames (builtins.getContext json);
      in concatMap (s: let
        matches = tfMatch s;
      in if matches != null then [] else [ s ]) drvs;
      references = if isTerraform then terraformReferencesString json ++ nonTfReferences else terraformReferencesDrv path;
      attrs = attrByPath (splitString "." "terraform.${path}") null config;
    in {
      ${path} = dagEntryAfter references ({
        inherit references;
      } // optionalAttrs isTerraform {
        terraform = attrs;
      } // optionalAttrs (!isTerraform) {
        drv = path;
      });
    };
    recurse = attrs: let
      paths = mapAttrsToList (k: v: v.data.references) attrs;
      paths' = concatLists paths;
      paths'' = filter (k: ! attrs ? ${k}) paths';
      next = recurse (attrs // dagsFor paths'');
    in if paths'' == [] then attrs else next;
    res = dagTopoSort (recurse (dagsFor v));
    res' = map ({ data, name }: nameValuePair name data.terraform or data.drv) res.result;
    res'' = listToAttrs res';
  in res') config.terranix.targets;
  tfFor = mapAttrs (k: v: let
    groupFn = item: if hasSuffix ".drv" item.name then "drv" else "terraform";
    tfs' = foldr (v: sum: if groupFn v == "terraform" then sum ++ [ v ] else []) [] v;
    tfs = if tfs' == [] then filter (v: groupFn v == "terraform") v else tfs';
    incomplete = (partition (v: groupFn v != "terraform" || any (i: i.name == v.name) tfs) v).wrong;
    toJson = { name, value }: foldr (key: attrs: { ${key} = attrs; }) value (splitString "." name);
    incomplete' = /*builtins.toJSON*/ (foldl recursiveUpdate {} (map toJson incomplete));
    targets = filter (name: hasPrefix "resource." name) (map (v: v.name) tfs);
    allTargets = filter (name: hasPrefix "resource." name) (map (v: v.name) v);
    out = /*builtins.toJSON*/ (foldl recursiveUpdate {} (map toJson tfs));
    out' = out // {
      provider = concatLists (mapAttrsToList (provider: v: mapAttrsToList (alias: v:
        {
          ${provider} = v // optionalAttrs (alias != "default") {
            inherit alias;
          };
        }) v
      ) (recursiveUpdate (incomplete'.provider or {}) (out.provider or {})));
    };
  in rec {
    complete = builtins.length incomplete == 0;
    inherit targets;
    providers = unique (map (target: elemAt (builtins.split "[._]" target) 2) allTargets);
    json = {
      data = out';
      rest = incomplete';
    };
  }) targets;
  terraformFor = {
    package ? pkgs.terraform_0_12
  , providers
  }: let
    translateProvider = provider: {
      google = "google-beta";
    }.${provider} or provider;
    mapProvider = p: provider: p.${translateProvider provider};
  in package.withPlugins (p: map (mapProvider p) providers);
  execFor = mapAttrs (k: v: let
    x = tfConfigDir {
      data = v.json;
      targets = if v.complete then [] else v.targets;
      terraform = terraformFor { inherit (v) providers; };
    };
  in "${x}/bin/terraform") tfFor;
  runFor = mapAttrs (k: v: let
    x = tfConfigDir {
      data = v.json;
      targets = if v.complete then [] else v.targets;
      terraform = terraformFor { inherit (v) providers; };
    };
  in x) tfFor;
  runForAll = mapAttrs (k: v: let
    x = tfConfigDir {
      data = v.json;
      targets = [];
      terraform = terraformFor { inherit (v) providers; };
    };
  in x) tfFor;
  apply = mapAttrs (k: v: let
    targets = concatStringsSep "," v.targets;
    x = ''
      set -eu

      ${runFor.${k}}/bin/terraform apply "$@"
    '' + optionalString (!v.complete) ''
      nix run -f ${toString ./.} apply.${k} --arg config ${toString config'} --arg terraformState $TF_STATE_FILE --argstr terraformTargets "${targets}" -c tf
    '';
    y = pkgs.writeShellScriptBin "tf" x;
  in y) tfFor;
  shellFor = mapAttrs (k: v: let
    TF_DIR = toString ./terraform;
    TF_STATE_FILE = "${TF_DIR}/terraform.tfstate";
    stateArg = "-state=${TF_STATE_FILE}";
    shell = pkgs.mkShell (commonEnv // {
      inherit TF_STATE_FILE TF_DIR;
      TF_DATA_DIR = "${TF_DIR}/data";
      TF_LOG_PATH = "${TF_DIR}/log.txt";
      TF_CLI_ARGS_plan = stateArg;
      TF_CLI_ARGS_apply = stateArg;
      TF_CLI_ARGS_state_list = stateArg;
      TF_CLI_ARGS_state_rm = stateArg;
      TF_CLI_ARGS_state_mv = stateArg;
      TF_CLI_ARGS_state_push = stateArg;
      TF_CLI_ARGS_state_pull = stateArg;
      TF_CLI_ARGS_state_show = stateArg;
      TF_CLI_ARGS_output = stateArg;
      TF_CLI_ARGS_destroy = stateArg;
      TF_CLI_ARGS_refresh = stateArg;
      shellHook = ''
        mkdir -p $TF_DATA_DIR
        HISTFILE=$TF_DIR/history
        unset SSH_AUTH_SOCK
      '';
    });
  in shell) tfFor;
}

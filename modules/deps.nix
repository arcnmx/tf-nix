{ pkgs, lib, config, ... }: with config.terraformConfig.lib.tf; with builtins; with lib; let
  dagEntryType = types.attrs;
  dagType = types.submodule ({ config, ... }: {
    options = {
      type = mkOption {
        type = types.enum [ "drv" "tf" ];
      };

      key = mkOption {
        type = types.str;
        default = null;
      };
    };
  });
  dagFromString = str: let
    tfDrv = terraformContextFromDrv str;
  in if tfDrv != null then {
    type = "tf";
    key = tfDrv.key;
  } else if hasSuffix ".drv" str then {
    type = "drv";
    key = str;
  } else {
    type = "tf";
    key = str;
  };

  # Sort a mixture of terraform resources and nix derivations by their interdependencies
  dagsFor' = paths: foldl (a: b: a // dagFor b) {} paths;
  dagFor = entry': let
    entry = dagFromString entry';
    target = fromHclPath entry.key;
    json = toJSON target.hcl;
    references = if entry.type == "tf" then mapAttrsToList (k: _: (dagFromString k).key) (getContext json) else terraformContextForDrv entry.key;
    #attrs = attrByPath (splitString "." "terraform.${path}") null config;
  in {
    ${entry.key} = dagEntryAfter references ({
      inherit references;
      inherit entry;
    } /*// optionalAttrs isTerraform {
      terraform = attrs;
    } // optionalAttrs (!isTerraform) {
      drv = path;
    }*/);
  };
  dagsFor = attrs: let
    paths = mapAttrsToList (k: v: v.data.references) attrs;
    paths' = concatLists paths;
    paths'' = filter (k: ! attrs ? ${k}) paths';
    next = dagsFor (attrs // dagsFor' paths'');
  in if paths'' == [] then attrs else next;
  /*
  tfFor = mapAttrs (k: v: let
    groupFn = item: if hasSuffix ".drv" item.name then "drv" else "terraform";
    tfs' = foldr (v: sum: if groupFn v == "terraform" then sum ++ [ v ] else []) [] v;
    tfs = if tfs' == [] then filter (v: groupFn v == "terraform") v else tfs';
    incomplete = (partition (v: groupFn v != "terraform" || any (i: i.name == v.name) tfs) v).wrong;
    toJson = { name, value }: foldr (key: attrs: { ${key} = attrs; }) value (splitString "." name);
    incomplete' = builtins.toJSON (foldl recursiveUpdate {} (map toJson incomplete));
    targets = filter (name: hasPrefix "resource." name) (map (v: v.name) tfs);
    allTargets = filter (name: hasPrefix "resource." name) (map (v: v.name) v);
    out = builtins.toJSON (foldl recursiveUpdate {} (map toJson tfs));
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
    shell = pkgs.mkShell (commonEnv // {
      inherit TF_STATE_FILE TF_DIR;
      TF_DATA_DIR = "${TF_DIR}/data";
      TF_LOG_PATH = "${TF_DIR}/log.txt";
      shellHook = ''
        mkdir -p $TF_DATA_DIR
        HISTFILE=$TF_DIR/history
        unset SSH_AUTH_SOCK
      '';
    });
  in shell) tfFor;*/
in {
  options = {
    terraformConfig = mkOption {
      type = types.unspecified;
      internal = true;
    };

    select = mkOption {
      type = types.listOf dagType;
      default = mapAttrsToList (_: r: dagFromString r.out.hclPathStr) config.terraformConfig.resources;
    };
    entries = mkOption {
      type = types.attrsOf dagEntryType;
      default = [ ];
    };
    sorted = mkOption {
      type = types.listOf dagType;
      readOnly = true;
    };
    hcl = mkOption {
      type = types.attrs;
      readOnly = true;
    };
    isComplete = mkOption {
      type = types.bool;
      readOnly = true;
    };
    targets = mkOption {
      type = types.listOf types.str;
      readOnly = true;
    };
  };

  config = let
    alltf = filter (e: e.type == "tf") config.sorted;
    tfs' = foldr (e: sum: if e.type == "tf" then sum ++ [ e ] else []) [] config.sorted;
    tfs = if tfs' == [] then filter (e: e.type == "tf") config.sorted else tfs';
    incomplete = (partition (e: e.type != "tf" || any (i: i.key == e.key) tfs) config.sorted).wrong;

    isComplete = incomplete == [ ];
    toHcl = r: hcl: let
      # TODO: this provider handling is hacky and meh
      hclPath = r.out.hclPath;
      path = if hasPrefix "provider." r.out.hclPathStr then [ "provider" r.type ] else hclPath;
    in attrsFromPath path (hcl r.hcl);
    hcl = foldl combineHcl { } (
      map (e: toHcl (fromHclPath e.key) scrubHcl) tfs
      ++ map (e: toHcl (fromHclPath e.key) scrubHclAll) incomplete
    );
    targets = map (r: r.out.reference) tfs;
    /*
    #toJson = { name, value }: foldr (key: attrs: { ${key} = attrs; }) value (splitString "." name);
    incomplete' = builtins.toJSON (foldl recursiveUpdate {} (map toJson incomplete));
    targets = filter (name: hasPrefix "resource." name) (map (v: v.name) tfs);
    allTargets = filter (name: hasPrefix "resource." name) (map (v: v.name) v);
    out = builtins.toJSON (foldl recursiveUpdate {} (map toJson tfs));*/
  in {
    entries = dagsFor (dagsFor' (map (t: t.key) config.select));
    sorted = map ({ data, name }: data.entry) (dagTopoSort config.entries).result;
    inherit hcl isComplete targets;
  };
}

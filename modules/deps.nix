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
  in {
    ${entry.key} = dagEntryAfter references {
      inherit references;
      inherit entry;
    };
  };
  dagsFor = attrs: let
    paths = mapAttrsToList (k: v: v.data.references) attrs;
    paths' = concatLists paths;
    paths'' = filter (k: ! attrs ? ${k}) paths';
    next = dagsFor (attrs // dagsFor' paths'');
  in if paths'' == [] then attrs else next;
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
    filterTarget = e: (fromHclPath e.key).out.dataType or null == "resource";
    targets = map (e: (fromHclPath e.key).out.reference) (filter filterTarget tfs);
  in {
    entries = dagsFor (dagsFor' (map (t: t.key) config.select));
    sorted = map ({ data, name }: data.entry) (dagTopoSort config.entries).result;
    inherit hcl isComplete targets;
  };
}

{ pkgs, lib, config, ... }: with config.lib.tf; with builtins; with lib; let
  cfg = config.deps;
  dagEntryType = types.attrs;
  dagType = types.submodule ({ config, ... }: {
    options = {
      type = mkOption {
        type = types.enum [ "drv" "path" "tf" ];
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
  } else if hasPrefix "/" str then {
    type = "path";
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
    references = if entry.type == "tf"
      then mapAttrsToList (k: _: (dagFromString k).key) (getContext json)
      else if entry.type == "drv" then terraformContextForDrv entry.key
      else [ ]; # TODO: consider including the entry.key path in dag? paths can't depend on anything though so are mostly useless?
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
  options.deps = {
    enable = mkEnableOption "terraform/nix DAG";

    select = {
      hclPaths = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        example = ''[ tfconfig.some_resource.out.hclPath ]'';
      };
      allProviders = mkOption {
        type = types.bool;
        default = false;
        description = "Deleted resources may require unused providers to be present in the config.";
      };
      providers = mkOption {
        type = types.listOf config.lib.tf.tfTypes.providerReferenceType;
        default = [ ];
      };
      allOutputs = mkOption {
        type = types.bool;
        default = true;
        description = "Export all outputs even if they're unused";
      };
      outputs = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
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

    apply = {
      package = mkOption {
        type = types.package;
        readOnly = true;
      };
      initCommand = mkOption {
        type = types.lines;
        defaultText = "terraform init";
      };
      doneCommand = mkOption {
        type = types.lines;
        default = "";
      };
    };
  };

  config = let
    # 1. remove any complete (or irrelevant) items from sorted
    filterDone = e: let
      hcl = fromHclPath e.key;
      name = hcl.out.reference;
      filteredNames = config.continue.input.populatedTargets;
      filtered = config.continue.present && (filteredNames == null || elem hcl.out.reference filteredNames);
    in e.type == "tf" && (hcl.kind == "variable" || hcl.kind == "provider" || filtered);
    done' = partition filterDone cfg.sorted;
    done = done'.right;
    remaining = done'.wrong;
    # 2. if sorted starts with drv entries, remove all until the first tf
    remaining' = (foldl (sum: e: if e.type == "drv" && !sum.fused
      then { fused = false; sum = [ ]; }
      else { fused = true; sum = sum.sum ++ [ e ]; }
    ) { fused = false; sum = [ ]; } remaining).sum;
    # 3. if sorted starts with any tf entries, apply all targets up until the first drv
    remaining'' = foldl (sum: e: if e.type == "tf" && sum.rest == [ ]
      then { rest = [ ]; tfs = sum.tfs ++ [ e ]; }
      else { rest = sum.rest ++ [ e ]; tfs = sum.tfs; }
    ) { tfs = [ ]; rest = [ ]; } remaining';
    tfTargets = remaining''.tfs;
    tfIncomplete = filter (e: e.type == "tf") remaining''.rest;
    # 4. if there are no drvs at the end, you're done. (no need to specify TF_TARGETS or continue)
    isComplete = remaining''.rest == [ ];
    # 5. if there are drvs at the end (and no more tfs), something is messed up?
    broken = !isComplete && all (e: e.type == "drv") remaining''.rest;


    toHcl = r: hcl: let
      # TODO: this provider handling is hacky and meh
      hclPath = r.out.hclPath;
      path = if hasPrefix "provider." r.out.hclPathStr then [ "provider" r.type ] else hclPath;
    in attrsFromPath path (hcl r.hcl);
    hcl = foldl combineHcl { } (
      map (e: toHcl (fromHclPath e.key) scrubHcl) (done ++ tfTargets)
      ++ map (e: toHcl (fromHclPath e.key) scrubHclAll) tfIncomplete
    ) // optionalAttrs (config.hcl.terraform != { }) { inherit (config.hcl) terraform; };

    filterTarget = e: let
      item = fromHclPath e.key;
    in item.kind == "resource" || item.kind == "data";
    targetMap = (e: (fromHclPath e.key).out.reference);
    targets = done ++ tfTargets;
    targetResources = filter filterTarget targets;

    select' =
      map (r: dagFromString r.out.provider.out.hclPathStr) cfg.select.providers
      ++ map (o: dagFromString config.outputs.${o}.out.hclPathStr) cfg.select.outputs
      ++ (if cfg.select.hclPaths == null
        then map (r: dagFromString r.out.hclPathStr) (filter (res: res.enable && !res.dataSource) (attrValues config.resources))
        else map (res: dagFromString res) cfg.select.hclPaths
      );
  in {
    deps = {
      entries = dagsFor (dagsFor' (map (t: t.key) select'));
      sorted = map ({ data, name }: data.entry) (dagTopoSort cfg.entries).result or (throw "tf-nix dependency loop detected");

      select = {
        providers = mkIf cfg.select.allProviders (mapAttrsToList (_: r: r.out.reference) config.providers);
        outputs = mkIf cfg.select.allOutputs (mapAttrsToList (_: o: o.name) config.outputs);
      };

      inherit isComplete;
      hcl = assert !broken; hcl;
      targets = map targetMap targetResources;

      apply = let
        targets = optionals (!cfg.isComplete) cfg.targets;
        # TODO: consider whether to include targets even on completion if not all resources are selected?
      in {
        package = pkgs.writeShellScriptBin "terraform-apply" (''
          set -eu

          export ${config.continue.envVar}='${toJSON config.continue.output.json}'
        '' + optionalString (!config.continue.present) cfg.apply.initCommand
        + "\n" + optionalString (config.continue.present) ''
          export TF_TARGETS="${concatStringsSep " " targets}"
          ${config.terraform.cli}/bin/terraform apply "$@"
        '' + (if !config.continue.present || !cfg.isComplete then escapeShellArgs config.runners.lazy.run.apply.out.runArgs + '' "$@"'' else cfg.apply.doneCommand));
        initCommand = "${config.terraform.cli}/bin/terraform init";
      };
    };
    continue.output.populatedTargets = mkIf cfg.enable (
      if config.continue.present then map targetMap targets else [ ]
    );
    terraform = {
      environment = mkIf cfg.enable {
        TF_CONFIG_DIR = mkDefault "${hclDir {
          inherit (cfg) hcl;
          inherit (config.terraform) prettyJson;
          terraform = config.terraform.packageWithPlugins;
        }}";
      };
    };
    runners.run = mkIf cfg.enable {
      apply = {
        executable = mkDefault "terraform-apply";
        package = mkDefault cfg.apply.package;
      };
    };
  };
}

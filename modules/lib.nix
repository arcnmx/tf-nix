{ pkgs, config, lib }: with builtins; with lib; let
  terraformExpr = expr: "\${${expr}}";
  # get all input context/dependencies for a derivation
  # https://github.com/NixOS/nix/issues/1245#issuecomment-401642781
  storeDirRe = replaceStrings [ "." ] [ "\\." ] builtins.storeDir;
  storeBaseRe = "[0-9a-df-np-sv-z]{32}-[+_?=a-zA-Z0-9-][+_?=.a-zA-Z0-9-]*";
  re = "(${storeDirRe}/${storeBaseRe}\\.drv)";
  # not a real parser (yet?)
  readDrv = pkg: let
    drv = readFile pkg;
    inputs = concatLists (filter isList (split re drv));
  in {
    inherit inputDrvs;
  };
  inputDrvs' = list: drvs:
    foldl (list: drv: if elem drv list then list else inputDrvs' (list ++ singleton drv) (readDrv drv).inputDrvs) list drvs;
  inputDrvs = drv: inputDrvs' [] [ drv ];

  # marker derivation for tracking (unresolved?) terraform resource dependencies, attaching context to json, etc.
  tfPrefix = "tf-1terraformReference-";
  tfMatch = match ".*-${tfPrefix}(.*)\\.drv";
  terraformContext = path: attr: let
    contextDrv = derivation {
      inherit (pkgs) system;
      name = "${tfPrefix}${path}";
      builder = "unresolved terraform reference";
      #__terraformPath = path;
    };
  in addContextFrom "${contextDrv}" "";

  # extract marker references
  terraformContextFor = target:
    if isString target && hasSuffix ".drv" target then terraformContextForDrv target
    else if target ? drvPath then terraformContextForDrv target.drvPath
    else terraformContextForString target;
  terraformContextForString = str: let
    drvs = attrNames (getContext str);
  in unique (concatMap (s: let
    context = terraformContextFromDrv s;
  in if context == null then [] else [ context.key ]) drvs);
  terraformContextForDrv = drv: let
    closure = inputDrvs drv;
  in unique (concatMap (s: let
    context = terraformContextFromDrv s;
  in if context == null then [] else context.key) closure);
  terraformContextFromDrv = drv: let
    matches = tfMatch drv;
  in if matches == null then null else {
    key = head matches;
  };

  # strip a string of all marker references
  removeTerraformContext = str: let
    context = filterAttrs (k: value: tfMatch k == null) (getContext str);
  in setContext context str;

  dag = import ./dag.nix { inherit lib; };
  run = import ./run.nix { inherit pkgs; };

  readState = statefile: let
    state = fromJSON (readFile statefile);
  in assert state.version == "4"; {
    inherit (state) outputs;
    # TODO: resource instances and state
  };

  # applies data from `builtins.getContext` back to a string.
  setContext = context: str: let
    str' = builtins.unsafeDiscardStringContext str;
  in foldl (str: cx: addContextFrom "${import cx}" str) str' (attrNames context); # TODO: preserve context outputs
in rec {
  inherit readDrv inputDrvs;
  inherit setContext;

  inherit readState;

  inherit terraformContext terraformContextFor terraformContextForString terraformContextForDrv terraformContextFromDrv removeTerraformContext;

  inherit terraformExpr;

  inherit (dag) dagTopoSort dagEntryAfter dagEntryBefore dagEntryAnywhere;
  inherit (run) nixRunWrapper;

  nixStoreUrl = config: {
    user ? "root"
  , attr ? "ipv4_address"
  , host ? terraformOutput config resource attr
  , resource ? null
  , path ? ""
  , private_key_file
  }: "ssh://${user}@${host}${path}?ssh-key=${private_key_file}";

  # TODO: secrets from env or elsewhere

  terraformModule = { config, ... }: {
    imports = [ ./terraform.nix ];
  };

  /*commonEnv = {
    TF_CLI_CONFIG_FILE = builtins.toFile "terraformrc" ''
      disable_checkpoint = true
    '';
    TF_INPUT = 0;
    TF_IN_AUTOMATION = 1;
    #TF_LOG = "INFO";
  };*/

  #references = terraformReferences example.config.nixos.system.build.toplevel;
  #references = inputDrvsRecursive [] [ example.config.nixos.system.build.toplevel.drvPath ];
}

{ lib }: with builtins; with lib; let
  terraformExpr = expr: "\${${expr}}";
  terraformSelf = attr: terraformExpr "self.${attr}";
  terraformIdent = id: replaceStrings [ "." ":" "/" ] [ "_" "_" "_" ] id; # https://www.terraform.io/docs/configuration/syntax.html#identifiers
  # get all input context/dependencies for a derivation
  # https://github.com/NixOS/nix/issues/1245#issuecomment-401642781
  storeDirRe = replaceStrings [ "." ] [ "\\." ] builtins.storeDir;
  storeBaseRe = "[0-9a-df-np-sv-z]{32}-[+_?=a-zA-Z0-9-][+_?=.a-zA-Z0-9-]*";
  re = "(${storeDirRe}/${storeBaseRe}\\.drv)";
  # not a real parser (yet?)
  readDrv = pkg: let
    drv = readFile pkg;
    inputDrvs = concatLists (filter isList (split re drv));
  in {
    inherit inputDrvs;
  };
  inputDrvs' = list: drvs:
    foldl (list: drv: if elem drv list then list else inputDrvs' (list ++ singleton drv) (readDrv drv).inputDrvs) list drvs;
  inputDrvs = drv: inputDrvs' [] [ drv ];

  # marker derivation for tracking (unresolved?) terraform resource dependencies, attaching context to json, etc.
  terraformContext = pkgs: resolved: path: attr: let
    contextDrv = derivation {
      inherit (pkgs) system;
      name = "tf-${if resolved then "2" else "1"}terraformReference-${path}";
      builder = if resolved
        then "${pkgs.coreutils}/bin/touch"
        else "unresolved terraform reference: ${path}" + optionalString (attr != null) ".${attr}";
      args = optionals resolved [ (placeholder "out") ];
      #__terraformPath = path;
    };
  in addContextFrom "${contextDrv}" "";
  terraformContextFromDrv = drvPath: let
    tfMatch = match ".*-tf-([12])terraformReference-(.*)\\.drv";
    matches = tfMatch drvPath;
  in mapNullable (match: {
    inherit drvPath;
    key = elemAt match 1;
    resolved = elemAt match 0 == "2";
  }) matches;

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
  in if context == null then [] else [ context.key ]) closure);

  # ugh
  fromHclPath = config: p: let
    path = if isString p then splitString "." p else p;
    name = last path;
    kind = head path;
    type = {
      resource = "resources";
      data = "resources";
      provider = "providers";
      output = "outputs";
      variable = "variables";
    }.${kind};
    cfg = config.${type};
    named = cfg.${name};
    nameOf = r: let
      alias = if r.alias != null then r.alias else r.type;
    in r.name or alias;
    find = findFirst (r: nameOf r == name) (throw "${toString p} not found") (attrValues cfg);
  in (if cfg ? ${name} && nameOf named == name then named else find) // {
    inherit kind;
  };

  combineHcl = a: b: recursiveUpdate a b // optionalAttrs (a ? provider || b ? provider) {
    provider = let
      plist = p: if isList p then p else singleton p;
    in plist a.provider or [] ++ plist b.provider or [];
  };

  scrubHclAll = hcl: let
    json = toJSON hcl;
    json' = unsafeDiscardStringContext json;
  in fromJSON json';
  scrubHcl = hcl: let
    json = removeTerraformContext (toJSON hcl);
    context = getContext json;
    json' = unsafeDiscardStringContext json;
  #in setContext context (fromJSON json');
  in mapAttrsRecursive (_: v:
    # HACK: just apply context to any string we can find in the attrset
    if isString v then setContext (context // getContext v) v else v
  ) (fromJSON json');

  providerPrefix = if versionAtLeast (versions.majorMinor version) "22.05"
    # this was changed in https://github.com/NixOS/nixpkgs/pull/155477
    then "libexec/terraform-providers"
    else "plugins";
  hclDir = {
    name ? "terraform"
  , hcl
  , pkgs ? import <nixpkgs> { }
  , terraform ? pkgs.buildPackages.terraform
  , jq ? pkgs.buildPackages.jq
  , generateLockfile ? versionAtLeast terraform.version or (builtins.parseDrvName terraform.name).version "0.14"
  , prettyJson ? false
  }: pkgs.stdenvNoCC.mkDerivation {
    name = "${name}.tf.json";
    allowSubstitutes = false;
    preferLocalBuild = true;

    nativeBuildInputs = optional generateLockfile terraform ++ optional prettyJson jq;
    passAsFile = [ "hcl" "script" "buildCommand" ];
    hcl = toJSON hcl;

    buildCommand = optionalString prettyJson ''
      jq -M . $hclPath > pretty.json
      hclPath=pretty.json
    '' + ''
      mkdir -p $out
      install -Dm0644 $hclPath $out/$name
    '' + optionalString generateLockfile ''
      terraform -chdir=$out providers lock \
        -fs-mirror=${terraform /* TODO resolve this properly if spliced */}/${providerPrefix} \
        -platform=${terraform.stdenv.hostPlatform.parsed.kernel.name + "_" + {
        x86_64 = "amd64";
        aarch64 = "arm64";
      }.${terraform.stdenv.hostPlatform.parsed.cpu.name} or (throw "unknown tf arch")}
    '';
  };

  # strip a string of all marker references
  removeTerraformContext = str: let
    context = filterAttrs (k: value: terraformContextFromDrv k == null) (getContext str);
  in setContext context str;

  dag = import ./dag.nix { inherit lib; };
  run = import ./run.nix { inherit lib; };

  readState = statefile: let
    state = fromJSON (readFile statefile);
  in assert state.version == "4"; {
    inherit (state) outputs;
    # TODO: resource instances and state
  };

  # applies data from `builtins.getContext` back to a string.
  setContext = let
    appendContext' = str: context: let
      contextToString = key: cx: let
        drv = import key;
      in if cx.path or false == true then "${/. + key}"
        else if cx ? outputs then concatMapStrings (flip getAttr drv) cx.outputs
        else throw "unknown context type for ${key}: ${toString (attrNames cx)}";
      context' = mapAttrsToList contextToString context;
    in foldl (flip addContextFrom) str context';
    appendContext = builtins.appendContext or appendContext';
  in context: str: appendContext (builtins.unsafeDiscardStringContext str) context;

  # attrsFromPath [ "a" "b" "c" ] x = { a.b.c = x }
  attrsFromPath = path: value: foldr (key: attrs: { ${key} = attrs; }) value path;
in rec {
  inherit readDrv inputDrvs;
  inherit setContext attrsFromPath;

  inherit readState;

  inherit terraformContext terraformContextFor terraformContextForString terraformContextForDrv terraformContextFromDrv removeTerraformContext;
  inherit fromHclPath combineHcl scrubHcl scrubHclAll hclDir;

  inherit terraformExpr terraformSelf terraformIdent;

  inherit (dag) dagTopoSort dagEntryAfter dagEntryBefore dagEntryAnywhere;
  inherit run;

  genUrl = {
    protocol
  , host
  , port ? null
  , user ? null
  , password ? null
  , path ? ""
  , queryString ? if query != { } then concatStringsSep "&" (mapAttrsToList (k: v: "${k}=${v}") query) else null
  , query ? { }
  , isUrl ? true
  }: let
    portDefaults = {
      ssh = 22;
      http = 80;
      https = 443;
    };
    explicitPort = port != null && (portDefaults.${protocol} or 0) != port;
    portStr = optionalString explicitPort ":${toString port}";
    queryStr = optionalString (queryString != null) "?${queryString}";
    passwordStr = optionalString (password != null) ":${password}";
    protocolStr = protocol + ":" + optionalString isUrl "//";
    creds = optionalString (user != null || password != null) "${toString user}${passwordStr}@";
  in "${protocolStr}${creds}${host}${portStr}${path}${queryStr}";

  # TODO: secrets from env or elsewhere
}

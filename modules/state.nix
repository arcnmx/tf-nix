{ config, lib, ... }: with lib; let
  cfg = config.state;
  v4 = state: let
    mapInstance = ins: let
      prefix = optionalString (ins.mode == "data") "data.";
      key = "${prefix}${ins.type}.${ins.name}";
      singular = nameValuePair key (head ins.instances).attributes;
    in map (ins: nameValuePair "${key}${optionalString (ins ? index_key) "[${ins.index_key}]"}" ins.attributes) ins.instances
      /*++ [ singular ]*/;
    filter = filterAttrs (k: _: cfg.filteredReferences == null || elem k cfg.filteredReferences);
  in {
    outputs = filter (mapAttrs' (k: v: nameValuePair "output.${k}" v.value) state.outputs);
    resources = filter (listToAttrs (concatMap mapInstance state.resources));
  };
in {
  options.state = {
    enable = mkEnableOption "tfstate" // {
      default = builtins.pathExists cfg.file;
    };
    file = mkOption {
      type = types.nullOr types.path;
      default = null;
    };
    filteredReferences = mkOption {
      type = types.nullOr (types.listOf types.str);
      default = null;
    };
  };

  config.state = let
    state = builtins.fromJSON (builtins.readFile cfg.file);
    out =
      if state.version == 4 then v4 state
      else throw "unsupported tfstate version ${state.version}";
    in mkIf cfg.enable {
      inherit (out) outputs resources;
    };
}

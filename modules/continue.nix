{ pkgs, config, lib, ... }: with lib; let
  cfg = config.continue;
  envStateStr = mapNullable builtins.getEnv cfg.envVar;
  envState =
    if envStateStr == null || envStateStr == "" then { }
    else builtins.fromJSON envStateStr;
in {
  options.continue = {
    present = mkOption {
      type = types.bool;
      default = cfg.input.depth > 0;
    };
    envVar = mkOption {
      type = types.nullOr types.str;
      default = "TF_NIX_CONTINUE";
    };
    input = {
      depth = mkOption {
        type = types.int;
        default = 0;
      };
      populatedTargets = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
      };
    };
    output = {
      populatedTargets = mkOption {
        type = types.nullOr (types.listOf types.str);
      };
      json = mkOption {
        type = types.attrsOf types.unspecified;
        readOnly = true;
      };
    };
  };
  config.continue = {
    input = {
      depth = mkIf (envState ? depth) envState.depth;
      populatedTargets = mkIf (envState ? populatedTargets) envState.populatedTargets;
    };
    output.json = {
      depth = cfg.input.depth + 1;
      populatedTargets = cfg.output.populatedTargets;
    };
  };
  config.state.filteredReferences = mkIf cfg.present (mkDefault cfg.input.populatedTargets);
}

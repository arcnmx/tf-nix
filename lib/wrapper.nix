# terraform wrapper supports extra environment variables:
# - TF_CONFIG_DIR: path to terraform configuration
# - TF_STATE_FILE: path to terraform state file (this *must not* be the same as $TF_DATA_DIR/terraform.tfstate)
# - TF_TARGETS: space-separated list of targets to select (terraform recommends not using this option)
{ lib, writeShellScriptBin, terraform }: with lib; writeShellScriptBin "terraform" ''
  set -eu

  if [[ -n ''${TF_CONFIG_DIR-} ]]; then
    case ''${1-} in
      init|plan|apply|destroy|providers|graph|refresh)
        set -- "$@" "$TF_CONFIG_DIR"
        ;;
    esac
    export TF_CLI_ARGS_import="''${TF_CLI_ARGS_import-} -config=$TF_CONFIG_DIR"
  fi
  if [[ -n ''${TF_DATA_DIR-} ]]; then
    mkdir -p "$TF_DATA_DIR"
  fi
  if [[ -n ''${TF_TARGETS-} ]]; then
    for target in $TF_TARGETS; do
      ${concatMapStringsSep "\n" (k: "export TF_CLI_ARGS_${k}=\"\${TF_CLI_ARGS_${k}-} -target=\$target\"") [ "plan" "apply" "destroy" ]}
    done
  fi
  if [[ -n ''${TF_STATE_FILE-} ]]; then
    ${concatMapStringsSep "\n" (k:
      "export TF_CLI_ARGS_${k}=\"\${TF_CLI_ARGS_${k}-} -state=$TF_STATE_FILE\""
    ) ([ "plan" "apply" "output" "destroy" "refresh" ] ++ map (a: "state_${a}") [ "list" "rm" "mv" "push" "pull" "show" "replace_provider" ])}
  fi
  exec ${terraform}/bin/terraform "$@"
''

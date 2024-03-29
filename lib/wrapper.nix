# terraform wrapper supports extra environment variables:
# - TF_CONFIG_DIR: path to terraform configuration
# - TF_STATE_FILE: path to terraform state file (this *must not* be the same as $TF_DATA_DIR/terraform.tfstate)
# - TF_TARGETS: space-separated list of targets to select (terraform recommends not using this option)
{ lib
, writeShellScriptBin
, terraform
, terraformVersion ? terraform.version or (builtins.parseDrvName terraform.name).version
}: with lib; writeShellScriptBin "terraform" ''
  set -eu

  TF_COMMAND=''${1-}
  if [[ -n ''${TF_CONFIG_DIR-} ]]; then
    case $TF_COMMAND in
      init|plan|apply|destroy|providers|graph|refresh|show|console)
        ${if versionAtLeast terraformVersion "0.14" then ''
          set -- -chdir="$TF_CONFIG_DIR" "$@"
        '' else ''
          set -- "$@" "$TF_CONFIG_DIR"
        ''}
        ;;
      import|state)
        ${optionalString (versionAtLeast terraformVersion "0.14") ''
          set -- -chdir="$TF_CONFIG_DIR" "$@"
        ''}
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
    ) ([ "plan" "apply" "output" "destroy" "refresh" "taint" "import" "console" ] ++ map (a: "state_${a}") [ "list" "rm" "mv" "push" "pull" "show" "replace_provider" ])}
    if [[ $TF_COMMAND = show ]]; then
      set -- "$@" "$TF_STATE_FILE"
    fi
  fi
  exec ${terraform}/bin/terraform "$@"
''

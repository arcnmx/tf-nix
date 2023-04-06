{ pkgs, runtimeShell ? pkgs.runtimeShell }: rec {
  nixRunner = binName: pkgs.stdenvNoCC.mkDerivation {
    preferLocalBuild = true;
    allowSubstitutes = false;
    name = "nix-run-wrapper-${binName}";
    defaultCommand = "bash"; # `nix run` execvp's bash by default
    inherit binName;
    inherit runtimeShell;
    passAsFile = [ "buildCommand" "script" ];
    buildCommand = ''
      mkdir -p $out/bin
      substituteAll $scriptPath $out/bin/$defaultCommand
      chmod +x $out/bin/$defaultCommand
      ln -s $out/bin/$defaultCommand $out/bin/run
    '';
    script = ''
      #!@runtimeShell@
      set -eu

      if [[ -n ''${NIX_NO_RUN-} ]]; then
        # escape hatch
        exec bash "$@"
      fi

      # also bail out if we're not called via `nix run`
      #PPID=($(@ps@/bin/ps -o ppid= $$))
      #if [[ $(readlink /proc/$PPID/exe) = */nix ]]; then
      #  exec bash "$@"
      #fi

      IFS=: PATHS=($PATH)
      join_path() {
        local IFS=:
        echo "$*"
      }

      # remove us from PATH
      OPATH=()
      for p in "''${PATHS[@]}"; do
        if [[ $p != @out@/bin ]]; then
          OPATH+=("$p")
        fi
      done
      export PATH=$(join_path "''${OPATH[@]}")

      exec @binName@ "$@" ''${NIX_RUN_ARGS-}
    '';
  };
  nixRunWrapper' = binName: package: pkgs.stdenvNoCC.mkDerivation {
    name = "nix-run-${binName}";
    preferLocalBuild = true;
    allowSubstitutes = false;
    wrapper = nixRunner binName;
    inherit package;
    passAsFile = [ "buildCommand" ];
    buildCommand = ''
      mkdir -p $out/nix-support
      echo $package $wrapper > $out/nix-support/propagated-user-env-packages
      if [[ -e $package/bin ]]; then
        ln -s $package/bin $out/bin
      fi
    '';
    meta = package.meta or {} // {
      mainProgram = package.meta.mainProgram or binName;
    };
    passthru = package.passthru or {};
  };
  nixRunWrapper = binName: package: if pkgs.lib.versionOlder builtins.nixVersion "2.4.0"
    then nixRunWrapper' binName package
    else package // {
      meta = package.meta or { } // {
        mainProgram = binName;
      };
    };
}

{
  compat = ./compat.nix;
  secrets = ./secrets.nix;
  secrets-users = ./secrets-users.nix;
  run = ../run.nix;

  # for installing over base images with lustrate
  ubuntu-linux = ./ubuntu-linux.nix;
  oracle-linux = ./oracle-linux.nix;

  # headless/vm settings
  vm = ./vm.nix;
  headless = ./headless.nix;

  # oci_core instances
  oracle = ./oracle.nix;

  # digitalocean droplets
  digitalocean = ./digitalocean.nix;

  __functor = self: { ... }: {
    imports = with self; [
      compat
      secrets
      secrets-users
      run
    ];
  };
}

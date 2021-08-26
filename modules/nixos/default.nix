{
  secrets = ./secrets.nix;
  secrets-users = ./secrets-users.nix;
  run = ../run.nix;

  __functor = self: { ... }: {
    imports = with self; [
      secrets
      secrets-users
      run
    ];
  };
}

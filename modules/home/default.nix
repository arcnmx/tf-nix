{
  secrets = ./secrets.nix;

  __functor = self: { ... }: {
    imports = with self; [
      secrets
    ];
  };
}

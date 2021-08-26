let
  tf = {
    acme = ./acme.nix;
    dns = ./dns.nix;
    terraform = ./terraform.nix;
    state = ./state.nix;
    deploy = ./deploy.nix;
    lustrate = ./lustrate.nix;
    run = ./run.nix;
    deps = ./deps.nix;
    continue = ./continue.nix;

    __functor = self: { ... }: {
      imports = with self; [
        acme
        dns
        terraform
        state
        deploy
        lustrate
        run
        deps
        continue
      ];
    };
  };
  nixos = import ./nixos;
  home = import ./home;
in {
  inherit tf home nixos;
} // tf

# tf-nix

[Terraform](https://www.terraform.io) and [Nix{,OS}](https://nixos.org/) all mashed together.

## Features and Goals

- [ ] NixOS deployment
- [ ] Secret and key deployment
- [ ] Health checks and maintenance commands
- [x] Pure nix configuration

## Example

Try out the [example](./example/example.nix):

```bash
export NIX_PATH="$NIX_PATH:tf=$PWD"
export TF_VAR_do_token=XXX
nix run tf.apply.server --arg config ./example/example.nix
```

## See Also

- [terranix](https://github.com/mrVanDalo/terranix)
- [terraform-nixos](https://github.com/tweag/terraform-nixos)
- [NixOps](https://nixos.org/nixops/)

# tf-nix

[Terraform](https://www.terraform.io) and [Nix{,OS}](https://nixos.org/) all mashed together.

## Example

Try out [example.nix](./example/example.nix):

```bash
export TF_VAR_do_token=XXX
nix-shell -E '(import ./. {}).shellFor.server' --run 'nix run -I tf=. tf.apply.server -c tf'
```

## See Also

- [terranix](https://github.com/mrVanDalo/terranix)
- [terraform-nixos](https://github.com/tweag/terraform-nixos)
- [NixOps](https://nixos.org/nixops/)

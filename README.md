# tf-nix

[Terraform](https://www.terraform.io) and [Nix{,OS}](https://nixos.org/) all mashed together.

## Features and Goals

- [ ] Health checks and maintenance commands
- [x] NixOS deployment
- [x] Secret and key deployment
- [x] Pure nix configuration

## Example

Try out the [example](./example/example.nix):

```bash
export TF_VAR_do_token=XXX
nix run -f. run.apply --arg config ./example/digitalocean.nix

# Now log into the server that was just deployed:
nix run -f. run.system-ssh --arg config ./example/digitalocean.nix

# To undo the above:
nix shell -f run.terraform --arg config ./example/digitalocean.nix -c terraform destroy
```

## See Also

- [terranix](https://github.com/mrVanDalo/terranix)
- [terraform-nixos](https://github.com/tweag/terraform-nixos)
- [NixOps](https://nixos.org/nixops/)
- [NixOSes](https://github.com/Infinisil/nixoses)

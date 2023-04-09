if nix --experimental-features "" shell --version 2>&1 >/dev/null; then
	exec nix --extra-experimental-features nix-command \
		shell "$@"
else
	exec nix \
		run "$@"
fi

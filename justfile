platform := `uname`
jobs := `nproc`

default:
  just {{ platform }}

Darwin:
	git add . ; nix run nix-darwin -- switch --flake .#cassandra

Linux:
	git add . ; nh os switch . --hostname jimbo -- --accept-flake-config

check:
	nix flake check --show-trace --max-jobs {{ jobs }}

repl:
	NIX_DEBUG=7 nix repl -f '<nixos>'


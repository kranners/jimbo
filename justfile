platform := `uname`
jobs := `nproc`

default:
  just {{ platform }}

Darwin:
	git add . ; nh darwin switch . --hostname cassandra

Linux:
	git add . ; nh os switch . --hostname jimbo

check:
	nix flake check --show-trace --max-jobs {{ jobs }}

repl:
	NIX_DEBUG=7 nix repl -f '<nixos>'


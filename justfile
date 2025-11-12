platform := `uname`

default:
  just {{ platform }}

Darwin:
	git add . ; nh darwin switch . --hostname piggys-MBP

Linux:
	git add . ; nh os switch . --hostname jimbo

check:
	nix flake check --show-trace

repl:
	NIX_DEBUG=7 nix repl -f '<nixos>'


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

quiet:
	just quiet-{{ platform }}

quiet-Darwin:
	git add .
	sudo darwin-rebuild switch --flake .#piggys-MBP

quiet-Linux:
	git add .
	sudo nixos-rebuild switch --flake .#jimbo

fmt:
	nix fmt

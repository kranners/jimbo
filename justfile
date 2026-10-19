platform := `uname`

# Macs whose LocalHostName is not their flake host fall back to piggys-MBP
darwin_host := `h=$(scutil --get LocalHostName 2>/dev/null); case "$h" in pilot) echo "$h" ;; *) echo piggys-MBP ;; esac`

default:
  just {{ platform }}

Darwin:
	git add . ; nh darwin switch . --hostname {{ darwin_host }}

Linux:
	git add . ; nh os switch .

check:
	nix flake check --show-trace

repl:
	NIX_DEBUG=7 nix repl -f '<nixos>'

quiet:
	just quiet-{{ platform }}

quiet-Darwin:
	git add .
	sudo darwin-rebuild switch --flake .#{{ darwin_host }}

quiet-Linux:
	git add .
	sudo nixos-rebuild switch --flake .

fmt:
	nix fmt

CURRENT_PLATFORM := $(shell uname)
MAX_JOBS := $(shell nproc)

switch:
ifeq ($(CURRENT_PLATFORM), Darwin)
	make darwin-switch
else
	make nixos-switch
endif

darwin-switch:
	git add . ; nix run nix-darwin -- switch --flake .#cassandra

nixos-switch:
	git add . ; nh os switch . --hostname jimbo
	
check:
	nix flake check --show-trace --max-jobs ${MAX_JOBS}

repl:
	NIX_DEBUG=7 nix repl -f '<nixos>'


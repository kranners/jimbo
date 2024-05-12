CURRENT_PLATFORM := $(shell uname)
MAX_JOBS := $(shell nproc)

switch:
	[[ "${CURRENT_PLATFORM}" = "Darwin" ]] && make darwin-switch || make nixos-switch

darwin-switch:
	git add . ; nh os switch . --hostname cassandra

nixos-switch:
	git add . ; nh os switch . --hostname jimbo
	
check:
	nix flake check --show-trace --max-jobs ${MAX_JOBS}

repl:
	NIX_DEBUG=7 nix repl -f '<nixos>'

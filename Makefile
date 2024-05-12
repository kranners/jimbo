MAX_JOBS := $(shell nproc)

darwin-switch:
	git add . ; nh os switch . --hostname cassandra

nixos-switch:
	git add . ; nh os switch . --hostname jimbo
	
check:
	nix flake check --show-trace --max-jobs ${MAX_JOBS}

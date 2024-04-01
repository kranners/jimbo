NIXNAME ?= jimbo
MAX_JOBS := $(shell nproc)

add-switch:
	git add . ; make switch

switch:
	sudo nixos-rebuild --flake ".#${NIXNAME}" --max-jobs ${MAX_JOBS} switch
	
boot:
	sudo nixos-rebuild --flake ".#${NIXNAME}" --max-jobs ${MAX_JOBS} boot
	
test:
	sudo nixos-rebuild --flake ".#${NIXNAME}" --max-jobs ${MAX_JOBS} test
	
rollback:
	sudo nixos-rebuild switch --rollback --max-jobs ${MAX_JOBS}

check:
	nix flake check --max-jobs ${MAX_JOBS}

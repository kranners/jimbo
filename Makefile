NIXNAME ?= jimbo

switch:
	sudo nixos-rebuild switch --flake ".#${NIXNAME}"
	
test:
	sudo nixos-rebuild test --flake ".#${NIXNAME}"

check:
	sudo nix flake check
	
cram:
	git add . ; git commit --amend --no-edit

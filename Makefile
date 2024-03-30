NIXNAME ?= jimbo

add-switch:
	git add . ; make switch

switch:
	sudo nixos-rebuild switch --flake ".#${NIXNAME}"
	
boot:
	sudo nixos-rebuild boot --flake ".#${NIXNAME}"
	
test:
	sudo nixos-rebuild test --flake ".#${NIXNAME}"
	
rollback:
	sudo nixos-rebuild switch --rollback

check:
	nix flake check

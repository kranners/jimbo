{
  # Should be able to remove this very soon
  darwinSystemModule = {
    nixpkgs.overlays = [
      (_self: super: {
        fish = super.fish.overrideAttrs {
          doCheck = false;
        };
      })
    ];
  };
}

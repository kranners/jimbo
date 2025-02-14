({ pkgs, config, lib, ... }: {
  options = {
    cow = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };

  config = {
    sharedHomeModule = {
      home.packages = lib.mkIf config.cow [ pkgs.cowsay ];
    };
  };
})

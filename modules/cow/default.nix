({ pkgs, config, lib, ... }: {
  options = {
    cow = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };

  config = {
    sharedHomeModule = lib.mkIf config.cow {
      home.packages = [ pkgs.cowsay ];
    };
  };
})

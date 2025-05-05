{
  nixosHomeModule = { config, ... }:
    let
      inherit (config.lib.file) mkOutOfStoreSymlink;
      ewwSourceHome = "${config.home.homeDirectory}/workspace/jimbo/modules/eww";
    in
    {
      programs.eww.enable = true;
      xdg.configFile.eww.source = mkOutOfStoreSymlink ewwSourceHome;
    };
}

{
  darwinHomeModule =
    { pkgs, ... }:
    let
      gnuToolsUnderGNames = pkgs.runCommandLocal "gnu-tools-under-g-names" { } ''
        mkdir -p $out/bin
        ln -s ${pkgs.gnused}/bin/sed $out/bin/gsed
        ln -s ${pkgs.gawk}/bin/gawk $out/bin/gawk
        ln -s ${pkgs.findutils}/bin/find $out/bin/gfind
        ln -s ${pkgs.findutils}/bin/xargs $out/bin/gxargs
        ln -s ${pkgs.gnugrep}/bin/grep $out/bin/ggrep
      '';
    in
    {
      home.packages = [
        pkgs.rtk
        pkgs.flock
        gnuToolsUnderGNames
      ];
    };
}

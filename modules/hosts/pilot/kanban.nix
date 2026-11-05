# The kanban board itself runs on spike (modules/hosts/spike/kanban.nix); pilot only runs sessions for it, through
# modules/kanban-runner. Its old local board and that board's `kanban-sync` updater are retired, and spike's
# `kanban-hub cutover` copies the local board's state across once. What stays here is cmux's socket password.
_: {
  darwinHomeModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      passwordFile = "${config.xdg.configHome}/kanban/cmux-socket-password";
      cmuxConfig = "${config.xdg.configHome}/cmux/cmux.json";
      cmuxSettings = pkgs.writeText "cmux.json" config.xdg.configFile.cmux.text;
    in
    {
      xdg.configFile.cmux.enable = false;

      home.activation.cmuxSocketPassword = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p "$(dirname ${passwordFile})" "$(dirname ${cmuxConfig})"
        [ -s ${passwordFile} ] || (umask 077; ${pkgs.openssl}/bin/openssl rand -hex 32 > ${passwordFile})
        (umask 077; ${pkgs.jq}/bin/jq --rawfile password ${passwordFile} \
          '.automation = { socketControlMode: "password", socketPassword: ($password | rtrimstr("\n")) }' \
          ${cmuxSettings} > ${cmuxConfig}.new)
        rm -f ${cmuxConfig}
        mv ${cmuxConfig}.new ${cmuxConfig}
      '';
    };
}

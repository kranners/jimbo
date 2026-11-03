{ host, lib, ... }:
let
  # spike's kanban tunnel may forward to the board's port on loopback and do nothing else, from spike alone.
  tunnelKey = import ../spike/kanban-remote-key.nix;
in
{
  darwinSystemModule.users.users.${host.username}.openssh.authorizedKeys.keys =
    lib.optional (tunnelKey != null)
      ''from="10.100.0.1",restrict,port-forwarding,permitopen="127.0.0.1:7420",command="/usr/bin/false" ${tunnelKey}'';

  darwinHomeModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      home = config.home.homeDirectory;
      passwordFile = "${config.xdg.configHome}/kanban/cmux-socket-password";
      cmuxConfig = "${config.xdg.configHome}/cmux/cmux.json";
      cmuxSettings = pkgs.writeText "cmux.json" config.xdg.configFile.cmux.text;
      checkout = "${home}/workspace/kanban";
      logs = "${home}/Library/Logs/kanban";
      path = lib.concatStringsSep ":" [
        "${pkgs.nodejs_24}/bin"
        "${home}/.local/bin"
        "/opt/homebrew/bin"
        "/etc/profiles/per-user/${config.home.username}/bin"
        "/run/current-system/sw/bin"
        "/usr/bin"
        "/bin"
        "/usr/sbin"
        "/sbin"
      ];
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

      launchd.agents.kanban = {
        enable = true;

        config = {
          Label = "kanban";
          ProgramArguments = [
            "${pkgs.nodejs_24}/bin/node"
            "--watch"
            "src/server/main.ts"
          ];
          WorkingDirectory = checkout;
          EnvironmentVariables = {
            KANBAN_AUTH = "off";
            PATH = path;
          };
          RunAtLoad = true;
          KeepAlive = true;
          StandardOutPath = "${logs}/server.log";
          StandardErrorPath = "${logs}/server.log";
        };
      };

      launchd.agents.kanban-sync = {
        enable = true;

        config = {
          Label = "kanban-sync";
          ProgramArguments = [
            "${pkgs.nodejs_24}/bin/node"
            "scripts/sync.ts"
          ];
          WorkingDirectory = checkout;
          EnvironmentVariables.PATH = path;
          RunAtLoad = true;
          StartInterval = 60;
          StandardOutPath = "${logs}/sync.log";
          StandardErrorPath = "${logs}/sync.log";
        };
      };
    };
}

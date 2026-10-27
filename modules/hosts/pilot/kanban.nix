{
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
          ProgramArguments = [
            "${pkgs.nodejs_24}/bin/node"
            "--watch"
            "src/server/main.ts"
          ];
          WorkingDirectory = "${home}/workspace/kanban";
          EnvironmentVariables = {
            KANBAN_AUTH = "off";
            PATH = lib.concatStringsSep ":" [
              "${home}/.local/bin"
              "/opt/homebrew/bin"
              "/etc/profiles/per-user/${config.home.username}/bin"
              "/run/current-system/sw/bin"
              "/usr/bin"
              "/bin"
              "/usr/sbin"
              "/sbin"
            ];
          };
          RunAtLoad = true;
          KeepAlive = true;
          StandardOutPath = "${home}/Library/Logs/kanban/server.log";
          StandardErrorPath = "${home}/Library/Logs/kanban/server.log";
        };
      };
    };
}

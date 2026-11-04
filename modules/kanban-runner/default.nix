# A kanban runner on each of Aaron's own machines, so the board on pilot can start sessions there.
# It reaches the board through spike's kanban.spike.cute.engineer, whose runner route passes only the runner
# endpoints and /runner.js through, and the board checks the shared token on each, so pilot opens no port.
# The token is KANBAN_RUNNER_TOKEN in ~/.config/kanban/env, mode 600, written by hand and never in this repository;
# until it is there the runner waits. jimbo runs it only while booted into NixOS.
{ host, lib, ... }:
let
  hosts = [
    "piggys-MBP"
    "jimbo"
  ];
  enabled = lib.elem host.hostname hosts;
  hub = "https://kanban.spike.cute.engineer";
  name = lib.toLower host.hostname;

  runner =
    pkgs:
    pkgs.writeShellApplication {
      name = "kanban-runner";
      runtimeInputs = [
        pkgs.nodejs_24
        pkgs.curl
        pkgs.coreutils
        pkgs.gnugrep
      ];
      text = ''
        env_file="$HOME/.config/kanban/env"
        cache="''${XDG_CACHE_HOME:-$HOME/.cache}/kanban-runner"
        token=$(grep -s '^KANBAN_RUNNER_TOKEN=' "$env_file" | head -n1 | cut -d= -f2- || true)
        if [ -z "$token" ]; then
          echo "kanban-runner: no KANBAN_RUNNER_TOKEN in $env_file yet, waiting" >&2
          sleep 300
          exit 0
        fi
        mkdir -p "$cache"
        # The board serves its own bundle to token holders, so the runner always matches the hub's code.
        if curl -fsS --max-time 60 -H @- -o "$cache/runner.js.new" ${hub}/runner.js <<<"Authorization: Bearer $token"; then
          mv "$cache/runner.js.new" "$cache/runner.js"
        fi
        [ -f "$cache/runner.js" ] || { echo "kanban-runner: can't fetch ${hub}/runner.js" >&2; sleep 60; exit 1; }
        exec node "$cache/runner.js" --hub ${hub} --name ${name}
      '';
    };
in
lib.optionalAttrs enabled {
  darwinHomeModule =
    { config, pkgs, ... }:
    {
      launchd.agents.kanban-runner = {
        enable = true;
        config = {
          Label = "kanban-runner";
          ProgramArguments = [ "${runner pkgs}/bin/kanban-runner" ];
          EnvironmentVariables.PATH = lib.concatStringsSep ":" [
            "${config.home.homeDirectory}/.local/bin"
            "/etc/profiles/per-user/${config.home.username}/bin"
            "/run/current-system/sw/bin"
            "/opt/homebrew/bin"
            "/usr/bin"
            "/bin"
          ];
          RunAtLoad = true;
          KeepAlive = true;
          ThrottleInterval = 30;
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/kanban-runner.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/kanban-runner.log";
        };
      };
    };

  nixosHomeModule =
    { config, pkgs, ... }:
    {
      systemd.user.services.kanban-runner = {
        Unit.Description = "kanban runner, sessions for the board on pilot";
        Service = {
          ExecStart = "${runner pkgs}/bin/kanban-runner";
          Environment = [
            "PATH=${config.home.homeDirectory}/.local/bin:/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin"
          ];
          Restart = "always";
          RestartSec = 30;
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
}

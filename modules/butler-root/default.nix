# Root for Butler, as Aaron asked on 6 Nov 2026: the login Butler uses on each machine may run commands as root, used
# only when needed and only where the daemon's gate lets it, a mission listing `root` for that machine or Aaron's yes
# for the one call, every root command logged to audit/root and `/revoke root` refusing it everywhere at once.
# On for spike and pilot since Aaron said go at 13:41 that day, off elsewhere: add a host to `on` below, or for pilot
# set its own line in modules/hosts/pilot/butler-root.nix, then run `just` there once (one Touch ID on a Mac).
# To take it away again, remove the host from `on` (or set pilot's line false) and run `just`: the sudoers entry and
# the helper go with the next switch, and nothing else is left behind.
{
  lib,
  config,
  host,
  ...
}:
let
  inherit (lib) mkOption mkIf types;
  cfg = config.butlerRoot;
  spike = "10.100.0.1";

  # Machines whose Butler login gets root once switched on; pilot is decided in its own file.
  on = [ "spike" ];
in
{
  options.butlerRoot.enable = mkOption {
    description = "Whether Butler's own login on this machine may run commands as root, through the daemon's root gate.";
    type = types.bool;
    default = builtins.elem host.hostname on;
  };

  # The Macs: Aaron's own `sudo` keeps its Touch ID prompt, and Butler gets one sudoers entry, for `butler-root`'s
  # helper alone, which runs its command as root only inside an ssh session from spike, the only place Butler's key
  # logs in from.
  config.darwinSystemModule = mkIf cfg.enable (
    { pkgs, ... }:
    let
      exec = pkgs.writeShellScript "butler-root-exec" ''
        set -u
        if [ "$(/usr/bin/id -u)" != 0 ] || [ $# -eq 0 ]; then
          echo "usage: butler-root <command> [args...]" >&2
          exit 2
        fi
        # Walk up from sudo to the process sshd started, and take root only when that session came from spike.
        pid=$PPID
        from=
        for _ in $(/usr/bin/seq 1 40); do
          parent=$(/bin/ps -o ppid= -p "$pid" 2> /dev/null | /usr/bin/tr -d ' ')
          [ -n "$parent" ] && [ "$parent" -gt 1 ] || break
          case "$(/bin/ps -o comm= -p "$parent" 2> /dev/null)" in
            *sshd*)
              from=$(/bin/ps -E -ww -o command= -p "$pid" 2> /dev/null | /usr/bin/grep -o 'SSH_CONNECTION=[0-9.]* ' | /usr/bin/cut -d= -f2 | /usr/bin/tr -d ' ')
              break
              ;;
          esac
          pid=$parent
        done
        if [ "$from" != "${spike}" ]; then
          echo "butler-root: only Butler's ssh session from spike may use this; use sudo yourself" >&2
          exit 77
        fi
        /usr/bin/logger -t butler-root -- "$*"
        exec "$@"
      '';
      shim = pkgs.writeShellScriptBin "butler-root" ''
        exec /usr/bin/sudo -n ${exec} "$@"
      '';
    in
    {
      environment.systemPackages = [ shim ];
      security.sudo.extraConfig = ''
        # Butler's root helper, from jimbo's butler-root module: Touch ID still guards every other sudo.
        ${host.username} ALL=(root) NOPASSWD: ${exec}
      '';
    }
  );

  # spike: Butler's scripts run as butler-shell, which gets passwordless sudo. The script still runs inside
  # butler-shell's sandbox, so root there reaches systemctl, the journal and what the sandbox leaves writable, never
  # /home, /etc or the store; NoNewPrivileges goes so the sudo wrapper can work at all.
  # jimbo's NixOS and framer need nothing: wheel's sudo there asks no password already, so on jimbo the gate is all
  # that holds Butler to the rule, and Butler has no login on framer.
  config.nixosSystemModule = mkIf (cfg.enable && host.hostname == "spike") {
    security.sudo.extraRules = [
      {
        users = [ "butler-shell" ];
        commands = [
          {
            command = "ALL";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
    systemd.services."butler-shell@".serviceConfig = {
      NoNewPrivileges = lib.mkForce false;
      ReadWritePaths = [ "-/run/sudo" ];
    };
  };
}

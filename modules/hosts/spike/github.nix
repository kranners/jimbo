{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.spike.github;

  # Runs a git command against GitHub, retrying it with backoff only when what it printed looks like GitHub or the
  # network failing, as on 4 Nov 2026, when GitHub's Git Operations incident refused every one of spike's keys now and
  # then for nearly two hours with `Permission denied (publickey)`; a lasting refusal still fails, after the last try.
  retry = pkgs.writeShellApplication {
    name = "github-retry";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
    text = ''
      [ $# -gt 0 ] || { echo "usage: github-retry <command...>" >&2; exit 2; }
      delays=(${lib.concatMapStringsSep " " toString cfg.retryDelays})
      attempts=$(( ''${#delays[@]} + 1 ))
      err=$(mktemp)
      trap 'rm -f "$err"' EXIT
      started=$SECONDS
      for (( attempt = 1; ; attempt++ )); do
        status=0
        "$@" 2>"$err" || status=$?
        cat "$err" >&2
        [ "$status" -ne 0 ] || exit 0
        if ! grep -qiE '${cfg.transientPattern}' "$err"; then
          exit "$status"
        fi
        if [ "$attempt" -ge "$attempts" ]; then
          echo "github-retry: $1 still failed after $attempts tries over $(( SECONDS - started ))s; GitHub or the network is refusing spike, and the next run tries again" >&2
          exit "$status"
        fi
        delay=$(( delays[attempt - 1] + RANDOM % 5 ))
        echo "github-retry: $1 failed ($(grep -m1 -iE '${cfg.transientPattern}' "$err" | cut -c1-120)), try $attempt of $attempts; retrying in ''${delay}s" >&2
        sleep "$delay"
      done
    '';
  };
in
{
  options.spike.github = {
    identities = mkOption {
      description = ''
        Every ssh identity spike uses to reach GitHub, one place naming each key, the user it runs as, the
        repositories it reaches and the units using it, which the units' GIT_SSH_COMMAND and the machines monitor's
        GitHub check both read. They stay separate keys, since one shared key would let each unit reach every other's
        repositories.
      '';
      type = types.attrsOf (
        types.submodule {
          options = {
            user = mkOption {
              type = types.str;
              description = "The user the units run git as, and the monitor's check runs ssh as.";
            };
            key = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "The private key, made by hand, or null for the user's own ssh config and default key.";
            };
            reaches = mkOption {
              type = types.str;
              description = "What GitHub lets it reach, in plain words.";
            };
            usedBy = mkOption {
              type = types.listOf types.str;
              description = "The units using it.";
            };
            fix = mkOption {
              type = types.str;
              description = "Where Aaron re-adds the key when GitHub has dropped it.";
            };
          };
        }
      );
    };

    retryDelays = mkOption {
      type = types.listOf types.int;
      default = [
        10
        30
        60
      ];
      description = "Seconds `github-retry` waits before each retry, plus up to 4 of jitter.";
    };

    transientPattern = mkOption {
      type = types.str;
      readOnly = true;
      default = "Permission denied \\(publickey\\)|Could not read from remote repository|Connection (reset|closed|timed out|refused)|kex_exchange_identification|ssh_exchange_identification|Could not resolve hostname|Operation timed out|remote end hung up|early EOF|unexpected disconnect|Internal Server Error|returned error: 5[0-9][0-9]|cannot lock ref";
      description = "What `github-retry` treats as GitHub or the network failing, worth another try.";
    };

    retry = mkOption {
      type = types.package;
      readOnly = true;
      default = retry;
      description = "`github-retry <command...>`, for a unit's fetch, clone or push.";
    };

    sshCommand = mkOption {
      type = types.functionTo types.str;
      readOnly = true;
      default =
        key:
        "ssh -i ${key} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20 -o ServerAliveInterval=15 -o ServerAliveCountMax=2";
      description = "The GIT_SSH_COMMAND for a key, given the path the unit sees it at.";
    };
  };

  config.spike.github.identities = {
    butler-daemon = {
      user = "butler";
      key = "/var/lib/butler/.ssh/claude-discord-threads-deploy";
      reaches = "kranners/claude-discord-threads, read-only";
      usedBy = [ "butler-pull" ];
      fix = "https://github.com/kranners/claude-discord-threads/settings/keys";
    };
    butler-memory = {
      user = "root";
      key = "/var/lib/secrets/butler-memory-deploy-key";
      reaches = "kranners/butler-memory, read-write";
      usedBy = [
        "butler-memory-pull"
        "butler"
        "butler-builders"
        "butler-probe-runner"
      ];
      fix = "https://github.com/kranners/butler-memory/settings/keys";
    };
    aaron = {
      user = "aaron";
      reaches = "every repository Aaron's account reaches, backlogic/backlogic and kranners/butler among them";
      usedBy = [
        "backlogic-lane-sweep-aaron"
        "backlogic-switch"
        "jimbo-switch"
      ];
      fix = "https://github.com/settings/keys";
    };
  };
}

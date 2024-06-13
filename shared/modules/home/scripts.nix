{ pkgs, ... }:
let
  kill-port = pkgs.writeShellApplication {
    name = "kill-port";

    # The first argument here is just the port you want to kill.
    # If given, a second argument will define the signal to send.
    text = ''
      PORT="$1"
      PID="$(lsof -i ":$PORT" | awk 'NR > 1 {print $2}')"

      if [ -z "$PID" ]; then
        echo "No process using port $PORT"
        return 0
      fi

      if kill -15 "$PID"; then
        echo "Killed $PID"
        return 0
      fi

      echo "Could not kill: $PID"
      return 1
    '';
  };

  show-pkg = pkgs.writeShellApplication {
    name = "show-pkg";

    runtimeInputs = [ pkgs.nix pkgs.eza ];

    text = ''
      PATHS="$(nix build "nixpkgs#$1" --print-out-paths --no-link)"

      for path in $PATHS; do
        eza "$path" --tree --level "''${2:-3}"
      done
    '';
  };

  find-pkg = pkgs.writeShellApplication {
    name = "find-pkg";

    text = ''
      nix-store --query --requisites /run/current-system | cut -d- -f2- | sort -u | grep "$1"
    '';
  };
in
{
  home.packages = [ kill-port show-pkg find-pkg ];
}

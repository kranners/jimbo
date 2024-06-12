{ pkgs
, inputs
, ...
}:
let
  nh-darwin = inputs.nh-darwin.packages.${pkgs.system}.nh;

  nuke-xcode = pkgs.writeShellApplication {
    name = "nuke-xcode";

    text = ''
      rm -rf "$HOME/Library/Developer/Xcode/DerivedData" && echo "❌ Deleted DerivedData"

      if [ ! -d "./Pods" ]; then
        echo "⏩ No Pods found in directory, skipping"
        exit 0;
      fi

      rm -rf "./Pods" && echo "❌ Deleted Pods"
      ( pod install )
    '';
  };

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
in
{
  imports = [ ./zsh.nix ./managers.nix ./android.nix ./git.nix ./secrets.nix ];

  home.packages = [
    nh-darwin

    nuke-xcode
    kill-port

    pkgs.nixpkgs-fmt
    pkgs.discord
    pkgs.nurl
    pkgs.eslint_d
  ];

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "23.11"; # Please read the comment before changing.
}

{ pkgs
, inputs
, ...
}:
let
  nh-darwin = inputs.nh-darwin.packages.${pkgs.system}.nh-darwin;

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

in
{
  imports = [ ./managers.nix ./android.nix ./secrets.nix ];

  home.packages = [
    nh-darwin

    nuke-xcode

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

{ pkgs, ... }:
let
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
  home.packages = [
    nuke-xcode
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

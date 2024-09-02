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
  home.home.packages = [ nuke-xcode ];
}

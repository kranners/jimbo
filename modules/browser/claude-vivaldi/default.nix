{ pkgs, lib }:

let
  claude =
    lib.findFirst (extension: extension.id == "fcoeoabgfenejglbffodgkkbkcdhcgfn")
      (throw "Claude in Chrome is missing from extensions.nix")
      (import ../extensions.nix { inherit pkgs; });

  senderIsSidePanel = ''(void 0===i.tab||!!i.tab.url?.startsWith(chrome.runtime.getURL("sidepanel.html")))'';
in
pkgs.runCommand "claude-vivaldi-${claude.version}"
  {
    nativeBuildInputs = [
      pkgs.unzip
      pkgs.jq
    ];
  }
  ''
    unzip -q ${claude.crxPath} -d $out || [ $? -eq 1 ]
    rm -r $out/_metadata
    cd $out

    cp ${./panel.html} vivaldi-panel.html
    cp ${./panel.js} vivaldi-panel.js

    # Vivaldi ignores chrome.sidePanel.setOptions: https://forum.vivaldi.net/topic/109300
    jq '.side_panel.default_path = "vivaldi-panel.html" | del(.update_url) | .name = "Claude (Vivaldi-patched)"' \
      manifest.json > manifest.patched.json
    mv manifest.patched.json manifest.json

    substituteInPlace assets/service-worker*.js \
      --replace-fail 'const r=void 0===i.tab,a=ao(i.origin)' 'const r=${senderIsSidePanel},a=ao(i.origin)' \
      --replace-fail 'if(void 0!==i.tab||!ao(i.origin))' 'if(!${senderIsSidePanel}||!ao(i.origin))'
  ''

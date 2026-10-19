{ pkgs, lib }:

let
  claude =
    lib.findFirst (extension: extension.id == "fcoeoabgfenejglbffodgkkbkcdhcgfn")
      (throw "Claude in Chrome is missing from extensions.nix")
      (import ../extensions.nix { inherit pkgs; });

  senderIsSidePanel =
    sender:
    ''(void 0===${sender}.tab||!!${sender}.tab.url?.startsWith(chrome.runtime.getURL("sidepanel.html")))'';
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
      --replace-fail 'const r=void 0===o.tab,i=bo(o.origin)' 'const r=${senderIsSidePanel "o"},i=bo(o.origin)' \
      --replace-fail 'if(void 0!==o.tab||!bo(o.origin))' 'if(!${senderIsSidePanel "o"}||!bo(o.origin))' \
      --replace-fail 'function Fi(e){return void 0===e.tab&&' 'function Fi(e){return ${senderIsSidePanel "e"}&&'
  ''

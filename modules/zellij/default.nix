{ inputs, ... }:
{
  sharedHomeModule =
    { pkgs, lib, ... }:
    let
      rust = (inputs.rust-overlay.lib.mkRustBin { } pkgs).stable.latest.minimal.override {
        targets = [ "wasm32-wasip1" ];
      };

      rustPlatform = pkgs.makeRustPlatform {
        cargo = rust;
        rustc = rust;
      };

      zellij-sidebar = pkgs.stdenv.mkDerivation {
        pname = "zellij-sidebar";
        version = "0.1.0";
        src = ./sidebar;

        cargoDeps = rustPlatform.importCargoLock { lockFile = ./sidebar/Cargo.lock; };
        nativeBuildInputs = [
          rust
          rustPlatform.cargoSetupHook
        ];

        buildPhase = ''
          cargo build --release --offline --target wasm32-wasip1
        '';

        installPhase = ''
          install -D target/wasm32-wasip1/release/zellij-sidebar.wasm $out/zellij-sidebar.wasm
        '';
      };

      zellij-sort-tabs = pkgs.writeShellApplication {
        name = "zellij-sort-tabs";
        runtimeInputs = [
          pkgs.zellij
          pkgs.jq
        ];

        text = ''
          tab_position() {
            zellij action list-tabs --json |
              jq --argjson tab "$1" '.[] | select(.tab_id == $tab) | .position'
          }

          SORTED_TAB_IDS="$(
            zellij action list-tabs --json | jq '
              def urgency: if startswith("input:") then 0 elif startswith("running:") then 1 else 2 end;
              sort_by((.name | urgency), .position) | .[].tab_id
            '
          )"

          TARGET=0
          for TAB_ID in $SORTED_TAB_IDS; do
            for ((POSITION = $(tab_position "$TAB_ID"); POSITION > TARGET; POSITION--)); do
              zellij action move-tab --tab-id "$TAB_ID" left
            done
            TARGET=$((TARGET + 1))
          done
        '';
      };

      zellij-agent-status = pkgs.writeShellApplication {
        name = "zellij-agent-status";
        runtimeInputs = [
          pkgs.zellij
          pkgs.jq
          zellij-sort-tabs
        ];

        text = ''
          [ -n "''${ZELLIJ:-}" ] || exit 0

          STATUS="''${1:-}"
          TAB_ID="$(
            zellij action list-panes --json |
              jq --argjson pane "$ZELLIJ_PANE_ID" '.[] | select((.is_plugin | not) and .id == $pane) | .tab_id'
          )"

          zellij action rename-tab --tab-id "$TAB_ID" "''${STATUS:+$STATUS: }$(basename "$PWD")"
          zellij-sort-tabs
        '';
      };

      goToTabBindings = lib.concatMapStrings (index: ''
        bind "Super Ctrl ${toString index}" { GoToTab ${toString index}; }
      '') (lib.range 1 9);
    in
    {
      home.packages = [
        pkgs.zellij
        zellij-agent-status
      ];

      xdg.configFile.zellij = {
        target = "./zellij/config.kdl";

        text = ''
          keybinds {
            shared {
              ${goToTabBindings}
              bind "Super Ctrl h" { MoveFocus "Left"; }
              bind "Super Ctrl j" { MoveFocus "Down"; }
              bind "Super Ctrl k" { MoveFocus "Up"; }
              bind "Super Ctrl l" { MoveFocus "Right"; }

              bind "Super Ctrl n" { NewPane "Right"; }
              bind "Super Ctrl Shift n" { NewPane "Down"; }
              bind "Super Ctrl w" { CloseFocus; }

              bind "Super Ctrl t" { NewTab; }
            }
          }
        '';
      };

      xdg.configFile.zellij-layout = {
        target = "./zellij/layouts/default.kdl";

        text = ''
          layout {
            pane split_direction="vertical" {
              pane size=28 borderless=true {
                plugin location="file:${zellij-sidebar}/zellij-sidebar.wasm"
              }
              pane
            }
            pane size=1 borderless=true {
              plugin location="zellij:status-bar"
            }
          }
        '';
      };
    };
}

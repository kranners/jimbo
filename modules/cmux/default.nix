{
  sharedHomeModule =
    { pkgs, ... }:
    let
      rename-workspace = pkgs.writeShellApplication {
        name = "rename-workspace";
        text = ''
          WORKSPACE_NAME="$(basename "$(pwd)")"
          cmux workspace-action --action rename --title "$WORKSPACE_NAME"
        '';
      };
    in
    {
      home.packages = [ rename-workspace ];

      xdg.configFile.cmux = {
        target = "./cmux/cmux.json";

        text = builtins.toJSON {
          shortcuts = {
            bindings = {
              focusLeft = "ctrl+cmd+h";
              focusDown = "ctrl+cmd+j";
              focusUp = "ctrl+cmd+k";
              focusRight = "ctrl+cmd+l";

              splitRight = "ctrl+cmd+n";
              splitDown = "ctrl+cmd+shift+n";
            };
          };
        };
      };
    };

  darwinHomeModule =
    { lib, ... }:
    {
      home.file.".claude/CLAUDE.md".text = lib.mkAfter ''
        To drive a browser, use cmux's: `cmux browser open <url>` prints its surface, then `cmux browser <surface> snapshot -i`, `click`, `fill` and `get`; `cmux browser --help` lists the rest.
        It holds a copy of Chromium's logins, refreshed with `cmux browser import --non-interactive --from chromium --profile Default --to-profile Default`.
      '';
    };
}

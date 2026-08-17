{
  sharedHomeModule = { pkgs, ... }:
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
    home.packages = [rename-workspace];

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
}

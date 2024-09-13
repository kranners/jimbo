{ pkgs, ... }:
let
  # FIXME: yucky, ew
  inherit (pkgs.hostPlatform) isDarwin;

  DARWIN_LATTE_ROOT = "/Users/aaronpierce/Documents/Latte";
  DARWIN_FRAPPUCCINO_ROOT = "/Users/aaronpierce/workspace/frappuccino/docs";

  NIXOS_LATTE_ROOT = "/home/aaron/Documents/Latte";
  NIXOS_FRAPPUCCINO_ROOT = "/home/aaron/workspace/frappuccino/docs";

  LATTE_ROOT = if isDarwin then DARWIN_LATTE_ROOT else NIXOS_LATTE_ROOT;
  FRAPPUCCINO_ROOT = if isDarwin then DARWIN_FRAPPUCCINO_ROOT else NIXOS_FRAPPUCCINO_ROOT;
in
{
  programs.nixvim = {
    extraConfigLua = builtins.readFile ./obsidian.lua;

    plugins.obsidian = {
      enable = true;

      settings = {
        workspaces = [
          {
            name = "Latte";
            path = LATTE_ROOT;
          }
          {
            name = "Frappuccino";
            path = FRAPPUCCINO_ROOT;
          }
        ];

        open_notes_in = "current";

        templates.subdir = "${LATTE_ROOT}/Templates";

        daily_notes = {
          date_format = "%Y/%m/%d %B, %Y";
          template = "Daily.md";
        };

        ui = {
          enable = false;

          checkboxes = {
            " " = {
              char = " ";
              hl_group = "ObsidianTodo";
            };
            "~" = {
              char = "~";
              hl_group = "ObsidianTilde";
            };
            x = {
              char = "x";
              hl_group = "ObsidianDone";
            };
          };
        };
      };
    };

    # See: https://github.com/epwalsh/obsidian.nvim/issues/286
    opts.conceallevel = 1;
  };
}

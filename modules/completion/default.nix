({ config, lib, ... }:
let
  is-blink-cmp = config.completion-engine == "blink-cmp";
  is-cmp = config.completion-engine == "cmp";
in
{
  options = {
    completion-engine = lib.mkOption {
      type = lib.types.enum [ "cmp" "blink-cmp" ];
      default = "cmp";
    };
  };

  config.sharedSystemModule.programs.nixvim = {
    plugins.blink-cmp = {
      enable = is-blink-cmp;

      settings = {
        keymap = {
          preset = "enter";

          "<CR>" = [ "accept" "fallback" ];
          "<Tab>" = [ "snippet_forward" "select_next" "fallback" ];
          "<S-Tab>" = [ "snippet_backward" "select_prev" "fallback" ];
        };

        appearance.nerd_font_variant = "mono";

        completion = {
          keyword.range = "full";
          accept.auto_brackets.enabled = true;
          list.selection.preselect = false;

          documentation = {
            auto_show = true;
            auto_show_delay_ms = 0;
          };

          ghost_text = {
            enabled = true;
          };
        };
      };
    };

    plugins.blink-ripgrep.enable = is-blink-cmp;
    plugins.cmp-nvim-lsp.enable = is-cmp;

    plugins.cmp = {
      enable = is-cmp;

      settings.sources = [
        { name = "nvim_lsp"; }

        { name = "buffer"; }
        { name = "path"; }
      ];

      settings.mapping = {
        "<CR>" = "cmp.mapping.confirm({ select = false })";

        "<Tab>" = "cmp.mapping(cmp.mapping.select_next_item(), {'i', 's'})";
        "<S-Tab>" = "cmp.mapping(cmp.mapping.select_prev_item(), {'i', 's'})";

        "<Down>" = "cmp.mapping(cmp.mapping.select_next_item(), {'i', 's'})";
        "<Up>" = "cmp.mapping(cmp.mapping.select_prev_item(), {'i', 's'})";
      };

      cmdline = {
        "/" = {
          mapping = {
            __raw = "cmp.mapping.preset.cmdline()";
          };
          sources = [{ name = "buffer"; }];
        };

        ":" = {
          mapping = {
            __raw = "cmp.mapping.preset.cmdline()";
          };
          sources = [
            { name = "path"; }
            {
              name = "cmdline";
              option = {
                ignore_cmds = [
                  "Man"
                  "!"
                ];
              };
            }
          ];
        };
      };
    };
  };
})

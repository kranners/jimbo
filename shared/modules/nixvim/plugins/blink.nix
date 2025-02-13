{
  programs.nixvim = {
    plugins.blink-cmp = {
      enable = true;

      settings = {
        keymap = {
          preset = "enter";

          "<CR>" = [ "accept" "fallback" ];
          "<Tab>" = [ "snippet_forward" "select_next" "fallback" ];
          "<S-Tab>" = [ "snippet_backward" "select_prev" "fallback" ];
        };

        appearance.nerd_font_variant = "mono";

        completion.list.selection.preselect = false;
      };
    };
    plugins.blink-ripgrep.enable = true;
  };
}

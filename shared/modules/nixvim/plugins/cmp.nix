{
  programs.nixvim = {
    # Sources
    plugins.cmp-nvim-lsp.enable = true;
    # plugins.cmp_yanky.enable = true;

    plugins.cmp = {
      enable = true;

      settings.sources = [
        { name = "nvim_lsp"; }
        { name = "luasnip"; }

        { name = "buffer"; }
        { name = "path"; }
      ];

      settings.mapping = {
        "<CR>" = "cmp.mapping.confirm({ select = true })";

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
}

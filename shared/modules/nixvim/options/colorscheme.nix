{
  programs.nixvim = {
    colorscheme = "cyberdream";
    opts.termguicolors = true;

    colorschemes.cyberdream = {
      enable = true;
      settings = {
        transparent = true;

        theme = {
          variant = "light";
        };

        extensions = {
          cmp = true;
          fzflua = true;
          grugfar = true;
          noice = true;
          notify = true;
          treesitter = true;
          rainbow_delimiters = true;
          trouble = true;
        };
      };
    };
  };
}

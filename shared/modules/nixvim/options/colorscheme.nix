{
  programs.nixvim = {
    colorscheme = "cyberdream";
    opts.termguicolors = true;

    colorschemes.cyberdream = {
      enable = true;

      settings.transparent = true;
    };
  };
}

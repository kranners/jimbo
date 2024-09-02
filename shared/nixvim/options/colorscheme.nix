{ pkgs, ... }: {
  programs.nixvim = {
    extraPlugins = [ pkgs.vimPlugins.onedarkpro-nvim ];

    colorscheme = "onedark_vivid";
    opts.termguicolors = true;
  };
}

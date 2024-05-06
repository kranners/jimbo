{ pkgs, ... }: {
  programs.nixvim = {
    extraPlugins = with pkgs.vimPlugins; [
      onedarkpro-nvim
    ];

    colorscheme = "onedark_vivid";
    opts.termguicolors = true;
  };
}

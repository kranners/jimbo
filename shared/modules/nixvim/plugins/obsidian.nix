{ pkgs, ... }: {
  programs.nixvim = {
    extraPlugins = [ pkgs.vimPlugins.obsidian-nvim ];
    extraConfigLua = builtins.readFile ./obsidian.lua;

    # See: https://github.com/epwalsh/obsidian.nvim/issues/286
    opts.conceallevel = 1;
  };
}

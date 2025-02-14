{ pkgs, ... }: {
  programs.nixvim = {
    extraPlugins = [ pkgs.vimPlugins.obsidian-nvim ];
    extraConfigLua = builtins.readFile ./obsidian.lua;
  };
}

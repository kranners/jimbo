{ pkgs, ... }: {
  programs.nixvim = {
    extraPlugins = [ pkgs.vimPlugins.obsidian-nvim ];
    extraConfigLua = builtins.readFile ./obsidian.lua;

    # See: https://github.com/epwalsh/obsidian.nvim/issues/286
    opts.conceallevel = 1;

    keymaps = [
      {
        key = "<Leader>d";
        action = "<CMD>ObsidianToday<CR>";
        options = { desc = "Open today's daily note"; };
        mode = "n";
      }
    ];
  };
}

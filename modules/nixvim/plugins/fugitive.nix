{ pkgs, ... }: {
  programs.nixvim = {
    extraPlugins = [ pkgs.vimPlugins.vim-rhubarb ];
    plugins.fugitive.enable = true;

    keymaps = [
      {
        key = "<C-m>";
        action = "<CMD>.GBrowse!<CR>";
        options = { desc = "Copy line permalink"; };
        mode = "n";
      }

      {
        key = "<Leader>m";
        action = "<CMD>.GBrowse<CR>";
        options = { desc = "Open line permalink"; };
        mode = "n";
      }
    ];
  };
}

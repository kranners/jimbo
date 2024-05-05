{
  programs.nixvim = {
    plugins.telescope = {
      enable = true;
      extensions = {
        fzf-native.enable = true;
      };
    };

    keymaps = [
      {
        key = "<C-f>";
        action = "<CMD>Telescope live_grep<CR>";
        options = {desc = "Fuzzy find file contents";};
        mode = "n";
      }

      {
        key = "<C-o>";
        action = "<CMD>Telescope find_files<CR>";
        options = {desc = "Find files by name";};
        mode = "n";
      }
    ];
  };
}

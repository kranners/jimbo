{
  programs.nixvim = {
    plugins.trouble.enable = true;

    keymaps = [
      {
        key = "<Leader>t";
        action = "<CMD>TroubleToggle<CR>";
        options = {desc = "Toggle view all issues";};
        mode = "n";
      }
    ];
  };
}

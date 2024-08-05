{ pkgs, ... }: {
  programs.nixvim = {
    plugins.spectre = {
      enable = true;

      findPackage = pkgs.ripgrep;
      replacePackage = pkgs.gnused;
    };

    keymaps = [
      {
        key = "<Leader>f";
        action = "<CMD>Spectre<CR>";
        options = { desc = "Toggle Spectre (search/replace)"; };
        mode = "n";
      }
    ];
  };
}

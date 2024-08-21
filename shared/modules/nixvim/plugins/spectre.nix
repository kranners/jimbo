{ pkgs, ... }: {
  programs.nixvim = {
    plugins.spectre = {
      enable = true;

      findPackage = pkgs.ripgrep;
      settings.default.replace.cmd = "oxi";
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

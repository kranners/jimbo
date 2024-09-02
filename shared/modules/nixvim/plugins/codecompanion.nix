{ pkgs, inputs, ... }:
let
  codecompanion = pkgs.vimUtils.buildVimPlugin {
    pname = "codecompanion";
    version = "2024-09-02";
    src = inputs.codecompanion;
    meta.homepage = "https://github.com/olimorris/codecompanion.nvim";
  };
in
{
  programs.nixvim = {
    plugins.copilot-vim.enable = true;

    extraPlugins = [ codecompanion ];
    extraConfigLua = ''
      require("codecompanion").setup({
        strategies = {
          chat = {
            adapter = "copilot",
          },
          inline = {
            adapter = "copilot",
          },
          agent = {
            adapter = "copilot",
          },
        },
      })
    '';

    keymaps = [
      {
        key = "<C-a>";
        action = "<CMD>CodeCompanionActions<CR>";
        options = { desc = "Show actions"; };
        mode = "n";
      }

      {
        key = "<Leader>a";
        action = "<CMD>CodeCompanionToggle<CR>";
        options = { desc = "Toggle Code Companion"; };
        mode = "n";
      }
    ];
  };
}

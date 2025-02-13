{ lib, inputs, pkgs, ... }:
let
  isDarwin = pkgs.hostPlatform.isDarwin;

  # use_shell attempts to start up the users shell before executing the Overseer job.
  # This is necessary for Darwin, but causes issues with the shell closing properly on NixOS.
  # https://github.com/stevearc/overseer.nvim/blob/master/lua/overseer/strategy/toggleterm.lua#L95
  toggleterm-use-shell-option = lib.optionalString isDarwin "use_shell = true,";
in
{
  programs.nixvim = {
    keymaps = [
      {
        key = "<BS>";
        action = "<CMD>OverseerRun<CR>";
        options = { desc = "Run task"; };
        mode = "n";
      }

      {
        key = "<C-BS>";
        action = "<CMD>OverseerQuickAction open float<CR>";
        options = { desc = "Open last task"; };
        mode = "n";
      }

      {
        key = "<Leader><BS>";
        action = "<CMD>OverseerToggle<CR>";
        options = { desc = "Toggle task view"; };
        mode = "n";
      }
    ];

    extraPlugins = with inputs.awesome-neovim-plugins.packages.${pkgs.system}; [
      overseer-nvim
      dressing-nvim
    ];

    extraConfigLua = ''
      require('overseer').setup({
        strategy = {
          "toggleterm",
          ${toggleterm-use-shell-option}
          open_on_start = false,
          hidden = true,
        },
        task_list = {
          direction = "bottom", 
          bindings = {
            ["<C-h>"] = "<CMD>wincmd h<CR>",
            ["<C-j>"] = "<CMD>wincmd j<CR>",
            ["<C-k>"] = "<CMD>wincmd k<CR>",
            ["<C-l>"] = "<CMD>wincmd l<CR>",
          },
        }
      })

      require('dressing').setup({
        input = {
          start_mode = "normal",
        },
      })
    '';
  };
}

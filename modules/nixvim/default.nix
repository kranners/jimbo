{ lib, config, ... }: {
  options.programs.nixvim = lib.mkOption {
    type = lib.types.deferredModule;
    default = { };
  };

  imports = [
    ./options
    ./plugins
  ];

  config.nixosSystemModule.programs.nixvim = config.programs.nixvim;
  config.darwinSystemModule.programs.nixvim = config.programs.nixvim;

  config.programs.nixvim = {
    enable = true;

    globals.mapleader = " ";

    keymaps = [
      {
        key = "<ESC>";
        action = "<C-\\><C-n>";
        options = { desc = "Move into normal mode in a terminal buffer"; };
        mode = "t";
      }

      {
        key = "<ESC>";
        action = "<CMD>nohlsearch<Bar>:echo<CR>";
        options = { desc = "Cancel search"; };
        mode = "n";
      }

      {
        key = "<Leader>s";
        action = "<CMD>wa<CR>";
        options = { desc = "Save all"; };
        mode = "n";
      }

      {
        key = "<C-[>";
        action = "<C-o>";
        options = { desc = "Jump back to last entry in jumplist"; };
        mode = "n";
      }

      {
        key = "<C-]>";
        action = "<C-i>";
        options = { desc = "Jump forward to next entry in jumplist"; };
        mode = "n";
      }

      {
        key = "\"\"";
        action = "<CMD>Telescope registers<CR>";
        options = { desc = "View the registers"; };
        mode = "n";
      }

      {
        key = "<C-c>";
        action.__raw = ''
          function()
            local current_filepath = vim.fn.getreg("%")
            vim.fn.setreg("@", current_filepath)

            vim.print(
              string.format("Yanked current filepath (%s)", current_filepath)
            )
          end
        '';
        options = { desc = "Copy current filepath"; };
        mode = "n";
      }
    ];
  };
}

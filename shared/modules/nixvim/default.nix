{
  imports = [
    ./options
    ./plugins
  ];

  programs.nixvim = {
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
            local current_position = vim.api.nvim_win_get_cursor(0)

            local row, column = unpack(current_position)

            local file_position = string.format(
              "%s:%s:%s", current_filepath, row, column
            )

            vim.fn.setreg("@", file_position)

            vim.print(
              string.format("Copied current position (%s)", file_position)
            )
          end
        '';
        options = { desc = "Copy current filepath"; };
        mode = "n";
      }
    ];
  };
}

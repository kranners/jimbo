return {
  "stevearc/oil.nvim",
  opts = {
    default_file_explorer = true,
    delete_to_trash = true,
    keymaps = {
      ["<C-c>"] = "actions.copy_entry_path",
      ["<C-h>"] = false,
      ["<C-l>"] = false,
      ["<C-r>"] = "actions.refresh",
    },
    skip_confirm_for_simple_edits = true,
    view_options = { natural_order = true, show_hidden = true },
    win_options = { wrap = true },
  },
  keys = {
    {
      "-",
      "<cmd>lua require('oil').open()<cr>",
      desc = "View files",
    },
  },
}

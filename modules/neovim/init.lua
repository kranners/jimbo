require("config.lazy")

require("notes")
require("terminals")
require("checkboxes")

vim.cmd([[colorscheme alabaster]])
vim.diagnostic.config({ virtual_text = false })

vim.opt.runtimepath:prepend(vim.fs.joinpath(vim.fn.stdpath("data"), "site"))

local binds_not_related_to_a_plugin = {
  {
    action = "<C-\\><C-n>",
    key = "<ESC>",
    mode = "t",
    options = { desc = "Move into normal mode in a terminal buffer" },
  },
  {
    action = "<CMD>nohlsearch<Bar>:echo<CR>",
    key = "<ESC>",
    mode = "n",
    options = { desc = "Cancel search" },
  },
  {
    action = "<CMD>wa<CR>",
    key = "<Leader>s",
    mode = "n",
    options = { desc = "Save all" },
  },
  {
    action = "<C-o>",
    key = "<C-[>",
    mode = "n",
    options = { desc = "Jump back to last entry in jumplist" },
  },
  {
    action = "<C-i>",
    key = "<C-]>",
    mode = "n",
    options = { desc = "Jump forward to next entry in jumplist" },
  },
  {
    action = function()
      local current_filepath = vim.fn.getreg("%")
      vim.fn.setreg("@", current_filepath)

      vim.print(string.format("Yanked current filepath (%s)", current_filepath))
    end,
    key = "<C-c>",
    mode = "n",
    options = { desc = "Copy current filepath" },
  },
  {
    action = "<CMD>split<CR>",
    key = "<Leader>n",
    mode = "n",
    options = { desc = "Make a new horizontal split" },
  },
  {
    action = "<CMD>vsplit<CR>",
    key = "<Leader>N",
    mode = "n",
    options = { desc = "Make a new vertical split" },
  },
  {
    action = "<CMD>wincmd h<CR>",
    key = "<C-h>",
    mode = { "t", "n", "i" },
    options = { desc = "Focus window left" },
  },
  {
    action = "<CMD>wincmd j<CR>",
    key = "<C-j>",
    mode = { "t", "n", "i" },
    options = { desc = "Focus window down" },
  },
  {
    action = "<CMD>wincmd k<CR>",
    key = "<C-k>",
    mode = { "t", "n", "i" },
    options = { desc = "Focus window up" },
  },
  {
    action = "<CMD>wincmd l<CR>",
    key = "<C-l>",
    mode = { "t", "n", "i" },
    options = { desc = "Focus window right" },
  },
  {
    action = "<CMD>wincmd H<CR>",
    key = "<Leader><Left>",
    mode = "n",
    options = { desc = "Send window to Left" },
  },
  {
    action = "<CMD>wincmd J<CR>",
    key = "<Leader><Down>",
    mode = "n",
    options = { desc = "Send window to Down" },
  },
  {
    action = "<CMD>wincmd K<CR>",
    key = "<Leader><Up>",
    mode = "n",
    options = { desc = "Send window to Up" },
  },
  {
    action = "<CMD>wincmd L<CR>",
    key = "<Leader><Right>",
    mode = "n",
    options = { desc = "Send window to Right" },
  },
  {
    action = "<CMD>vertical resize +5<CR>",
    key = "<Left>",
    mode = "n",
  },
  {
    action = "<CMD>resize +5<CR>",
    key = "<Down>",
    mode = "n",
  },
  {
    action = "<CMD>resize -5<CR>",
    key = "<Up>",
    mode = "n",
  },
  {
    action = "<CMD>vertical resize -5<CR>",
    key = "<Right>",
    mode = "n",
  },
  {
    key = "<Leader><CR>",
    action = "<CMD>lua vim.lsp.buf.code_action()<CR>",
    mode = "n",
    desc = "Show code actions",
  },
  {
    key = "<Leader>r",
    action = "<CMD>lua vim.lsp.buf.rename()<CR>",
    mode = "n",
    desc = "Rename symbol",
  },
}

for _, bind in ipairs(binds_not_related_to_a_plugin) do
  vim.keymap.set(bind.mode, bind.key, bind.action, bind.options)
end

vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
  pattern = { "*.json" },
  callback = function()
    vim.opt.conceallevel = 0
  end,
})

vim.api.nvim_create_user_command("Z", function()
  vim.cmd("wa!")
  vim.cmd("qa!")
end, {})

vim.cmd("cabbrev wqa Z")

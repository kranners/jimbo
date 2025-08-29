require("config.lazy")

-- Nixvim's internal module table
-- Can be used to share code throughout init.lua
local _M = {}

vim.cmd [[colorscheme cyberdream]]
vim.diagnostic.config({ virtual_text = false })

vim.opt.runtimepath:prepend(vim.fs.joinpath(vim.fn.stdpath("data"), "site"))

-- Set up keybinds {{{
do
  local __nixvim_binds = {
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
      action = "<CMD>Telescope registers<CR>",
      key = '""',
      mode = "n",
      options = { desc = "View the registers" },
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
      action = "<CMD>lua vim.lsp.buf.code_action()<CR>",
      key = "<Leader><CR>",
      mode = "n",
      options = { desc = "Show code actions" },
    },
    {
      action = "<CMD>lua vim.lsp.buf.rename()<CR>",
      key = "<Leader>r",
      mode = "n",
      options = { desc = "Rename symbol" },
    },
    {
      action = "<CMD>OverseerRun<CR>",
      key = "<BS>",
      mode = "n",
      options = { desc = "Run task" },
    },
    {
      action = "<CMD>OverseerQuickAction open float<CR>",
      key = "<C-BS>",
      mode = "n",
      options = { desc = "Open last task" },
    },
    {
      action = "<CMD>OverseerToggle<CR>",
      key = "<Leader><BS>",
      mode = "n",
      options = { desc = "Toggle task view" },
    },
    {
      action = "<CMD>TSJJoin<CR>",
      key = "<Leader>j",
      mode = "n",
      options = { desc = "Join object together" },
    },
    {
      action = "<CMD>TSJSplit<CR>",
      key = "<Leader>k",
      mode = "n",
      options = { desc = "Split object apart" },
    },
    {
      action = "<CMD>TSJToggle<CR>",
      key = "<Leader>m",
      mode = "n",
      options = { desc = "Toggle single vs multiline" },
    },
    {
      action = "<CMD>BufferCloseAllButVisible<CR>",
      key = "<Leader>w",
      mode = "n",
      options = { desc = "Clean invisible buffers" },
    },
    {
      action = function()
        require("resession").save(vim.fn.getcwd(), { dir = "dirsession" })
      end,
      key = "<Leader>S",
      mode = "n",
      options = { desc = "Save session" },
    },
    {
      action = "<CMD>GrugFar<CR>",
      key = "<Leader>f",
      mode = "n",
      options = { desc = "Open search-replace vertical buffer" },
    },
    {
      action = "<CMD>NoNeckPain<CR>",
      key = "<Leader>z",
      mode = "n",
      options = { desc = "Toggle neck pain" },
    },
    {
      action = "<CMD>ZenMode<CR>",
      key = "<S-z>",
      mode = "n",
      options = { desc = "Toggle zen mode" },
    },
    {
      action = function()
        Snacks.picker.lsp_definitions()
      end,
      key = "]]",
      mode = "n",
      options = { desc = "Search definitions" },
    },
    {
      action = function()
        Snacks.picker.lsp_references()
      end,
      key = "[[",
      mode = "n",
      options = { desc = "Search references" },
    },
    {
      action = function()
        Snacks.picker.grep()
      end,
      key = "<C-f>",
      mode = "n",
      options = { desc = "Fuzzy find file contents" },
    },
    {
      action = function()
        Snacks.picker.buffers()
      end,
      key = "<C-b>",
      mode = "n",
      options = { desc = "Search through current buffers" },
    },
    {
      action = function()
        Snacks.picker.files()
      end,
      key = "<C-o>",
      mode = "n",
      options = { desc = "Find files by name" },
    },
    {
      action = function()
        Snacks.picker.diagnostics()
      end,
      key = "<C-q>",
      mode = "n",
      options = { desc = "Show diagnostics" },
    },
    {
      action = function()
        Snacks.picker.keymaps()
      end,
      key = "<C-p>",
      mode = "n",
      options = { desc = "Show keymaps" },
    },
    {
      action = "<CMD>.GBrowse!<CR>",
      key = "<C-m>",
      mode = "n",
      options = { desc = "Copy line permalink" },
    },
    {
      action = "<CMD>.GBrowse<CR>",
      key = "<Leader>m",
      mode = "n",
      options = { desc = "Open line permalink" },
    },
    {
      action = "<CMD>EagleWin<CR>",
      key = "<CR>",
      mode = "n",
      options = { desc = "Open Eagle hover window 🦅", silent = true },
    },
  }
  for _, map in ipairs(__nixvim_binds) do
    vim.keymap.set(map.mode, map.key, map.action, map.options)
  end
end
-- }}}

-- package.path = package.path .. ";" .. "/Users/aaronpierce/.config/nvim/?.lua"
require("notes")
require("terminals")

vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
  pattern = { "*.json" },
  callback = function()
    vim.opt.conceallevel = 0
  end,
})

-- Set up autogroups {{
do
  local __nixvim_autogroups = { nixvim_binds_LspAttach = { clear = true } }

  for group_name, options in pairs(__nixvim_autogroups) do
    vim.api.nvim_create_augroup(group_name, options)
  end
end
-- }}
-- Set up autocommands {{
do
  local __nixvim_autocommands = {
    {
      callback = function(args)
        do
          local __nixvim_binds = {}

          for _, map in ipairs(__nixvim_binds) do
            local options = vim.tbl_extend("keep", map.options or {}, { buffer = args.buf })
            vim.keymap.set(map.mode, map.key, map.action, options)
          end
        end
      end,
      desc = "Load keymaps for LspAttach",
      event = "LspAttach",
      group = "nixvim_binds_LspAttach",
    },
    {
      callback = function()
        -- Only load the session if nvim was started with no args
        if vim.fn.argc(-1) == 0 then
          -- Save these to a different directory, so our manual sessions don't get polluted
          require("resession").load(vim.fn.getcwd(), { dir = "dirsession", silence_errors = true })
        end
      end,
      event = { "VimEnter" },
      nested = true,
    },
    {
      callback = function()
        require("resession").save(vim.fn.getcwd(), { dir = "dirsession" })
      end,
      event = { "VimLeavePre" },
      nested = false,
    },
  }

  for _, autocmd in ipairs(__nixvim_autocommands) do
    vim.api.nvim_create_autocmd(autocmd.event, {
      group = autocmd.group,
      pattern = autocmd.pattern,
      buffer = autocmd.buffer,
      desc = autocmd.desc,
      callback = autocmd.callback,
      command = autocmd.command,
      once = autocmd.once,
      nested = autocmd.nested,
    })
  end
end
-- }}
--
--
vim.cmd("cnoreabbrev norm Norm")

vim.api.nvim_create_autocmd("TermOpen", {
  callback = function()
    vim.opt_local.number = true
    vim.opt_local.relativenumber = true
  end,
})

vim.api.nvim_create_user_command("Z", function()
  vim.cmd("wa!")
  vim.cmd("qa!")
end, {})

vim.cmd("cabbrev wqa Z")

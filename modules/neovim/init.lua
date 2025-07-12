require("plugins")

-- Nixvim's internal module table
-- Can be used to share code throughout init.lua
local _M = {}

-- Set up globals {{{
do
  local nixvim_globals = {
    mapleader = " ",
    maplocalleader = ",",
    -- Ensure conceallevel is set to 0 on JSON
    -- https://github.com/nvim-treesitter/nvim-treesitter/issues/2825#issuecomment-1496747076
    indentLine_fileTypeExclude = { "dashboard", "json", "markdown" }
  }

  for k, v in pairs(nixvim_globals) do
    vim.g[k] = v
  end
end
-- }}}

-- Set up options {{{
do
  local nixvim_options = {
    conceallevel = 0,
    equalalways = false,
    expandtab = true,
    number = true,
    relativenumber = true,
    shiftwidth = 0,
    swapfile = false,
    tabstop = 2,
    termguicolors = true,
  }

  for k, v in pairs(nixvim_options) do
    vim.opt[k] = v
  end
end
-- }}}

require("nvim-surround").setup({})

require("cyberdream").setup({
  extensions = {
    cmp = true,
    fzflua = true,
    grugfar = true,
    noice = true,
    notify = true,
    rainbow_delimiters = true,
    treesitter = true,
    trouble = true,
  },
  theme = { variant = "dark" },
  transparent = true,
})

vim.diagnostic.config({ virtual_text = false })

vim.cmd([[colorscheme cyberdream
]])
require("nvim-web-devicons").setup({})

-- LSP {{{
do
  local __lspServers = {
    { name = "yamlls" },
    {
      extraOptions = {
        filetypes = {
          "javascript",
          "javascriptreact",
          "javascript.jsx",
          "typescript",
          "typescriptreact",
          "typescript.tsx",
        },
        init_options = {
          preferences = {
            importModuleSpecifierPreference = "non-relative",
            includeInlayEnumMemberValueHints = true,
            includeInlayFunctionLikeReturnTypeHints = true,
            includeInlayFunctionParameterTypeHints = true,
            includeInlayParameterNameHints = "all",
            includeInlayParameterNameHintsWhenArgumentMatchesName = true,
            includeInlayPropertyDeclarationTypeHints = true,
            includeInlayVariableTypeHints = true,
          },
        },
      },
      name = "ts_ls",
    },
    { name = "terraformls" },
    { name = "ruby_lsp" },
    {
      extraOptions = {
        settings = {
          nixd = {
            formatting = {
              command = { "nixpkgs-fmt" },
            },
          },
        },
      },
      name = "nixd",
    },
    { name = "lua_ls" },
    { name = "jsonls" },
    { name = "html" },
    { name = "gopls" },
    { name = "eslint" },
    { name = "emmet_language_server" },
    { name = "astro" },
    { name = "ruff" },
    { name = "jedi_language_server" },
    {
      extraOptions = {
        settings = {
          basedpyright = {
            typeCheckingMode = "basic",
          },
        },
      },
      name = "basedpyright",
    },
  }

  -- Adding lspOnAttach function to nixvim module lua table so other plugins can hook into it.
  _M.lspOnAttach = function(client, bufnr) end
  local __lspCapabilities = function()
    capabilities = vim.lsp.protocol.make_client_capabilities()

    capabilities = vim.tbl_deep_extend("force", capabilities, require("cmp_nvim_lsp").default_capabilities())

    return capabilities
  end

  local __setup = {
    on_attach = _M.lspOnAttach,
    capabilities = __lspCapabilities(),
  }

  for i, server in ipairs(__lspServers) do
    if type(server) == "string" then
      require("lspconfig")[server].setup(__setup)
    else
      local options = server.extraOptions

      if options == nil then
        options = __setup
      else
        options = vim.tbl_extend("keep", options, __setup)
      end

      require("lspconfig")[server.name].setup(options)
    end
  end
end
-- }}}

local cmp = require("cmp")
cmp.setup({
  mapping = {
    ["<CR>"] = cmp.mapping.confirm({ select = false }),
    ["<Down>"] = cmp.mapping(cmp.mapping.select_next_item(), { "i", "s" }),
    ["<S-Tab>"] = cmp.mapping(cmp.mapping.select_prev_item(), { "i", "s" }),
    ["<Tab>"] = cmp.mapping(cmp.mapping.select_next_item(), { "i", "s" }),
    ["<Up>"] = cmp.mapping(cmp.mapping.select_prev_item(), { "i", "s" }),
  },
  sources = { { name = "nvim_lsp" }, { name = "buffer" }, { name = "path" } },
})

cmp.setup.cmdline("/", { mapping = cmp.mapping.preset.cmdline(), sources = { { name = "buffer" } } })

cmp.setup.cmdline(
  ":",
  {
    mapping = cmp.mapping.preset.cmdline(),
    sources = { { name = "path" }, { name = "cmdline", option = { ignore_cmds = { "Man", "!" } } } },
  }
)

vim.opt.runtimepath:prepend(vim.fs.joinpath(vim.fn.stdpath("data"), "site"))
require("nvim-treesitter.configs").setup({
  ensure_installed = {
    "javascript",
    "tsx",
    "typescript",
    "python",
    "lua",
    "luadoc",
    "markdown",
    "vim",
    "vimdoc",
    "nix",
    "bash",
    "css",
    "diff",
    "graphql",
    "json",
    "just",
    "kotlin",
    "java",
    "swift",
    "scss",
    "yuck",
  },
  highlight = { additional_vim_regex_highlighting = false, enable = true },
  indent = { enable = true },
  parser_install_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "site"),
})

require("render-markdown").setup({
  anti_conceal = { enabled = true },
  preset = "obsidian",
  pipe_table = {
    style = "normal",
  },
})

require("oil").setup({
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
})

require("nvim-lightbulb").setup({})

require("nvim-autopairs").setup({})

require("noice").setup({
  health = { checker = false },
  routes = { { filter = { event = "msg_showmode" }, view = "notify" } },
  views = { cmdline_popup = { win_options = { winhighlight = "NormalFloat:NormalFloat,FloatBorder:FloatBorder" } } },
})

require("neoscroll").setup({})

require("lualine").setup({
  sections = {
    lualine_x = {
      {
        function()
          local mode = require("noice").api.statusline.mode
          if mode.has() then
            local content = mode.get()
            if string.match(content, "^recording @%w$") then
              return content
            end
          end
          return ""
        end,
        color = { fg = "#ff9e64" },
      },
    },
  },
})

require("ibl").setup({})

require("gitsigns").setup({})

require("fzf-lua").setup({ "telescope" })

require("conform").setup({
  format_on_save = { lsp_fallback = true, timeout_ms = 500 },
  formatters_by_fmt = {
    javascript = { { "eslint_d", "prettierd" } },
    javascriptreact = { { "eslint_d", "prettierd" } },
    ruby = { "rubocop" },
    typescript = { { "eslint_d", "prettierd" } },
    typescriptreact = { { "eslint_d", "prettierd" } },
  },
})

require("Comment").setup({ mappings = { basic = false, extra = false } })

require("colorizer").setup({})

require("codesnap").setup({ bg_color = "#ffffff00", code_font_family = "Iosevka Nerd Font Mono", watermark = "" })

require("snacks").setup({
  picker = {
    main = {
      file = false,
      current = true,
    },
    formatters = {
      file = {
        filename_first = false,
        truncate = 10000,
      },
    },
  },
})

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
      action = "<cmd>lua require('oil').open()<cr>",
      key = "-",
      mode = "n",
      options = { desc = "View files" },
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
      action = "<CMD>lua require('Comment.api').toggle.linewise.current()<CR><C-o>$",
      key = "<C-/>",
      mode = "i",
      options = { desc = "Toggle comment on current line (insert mode) " },
    },
    {
      action = "<PLUG>(comment_toggle_linewise_current)",
      key = "<C-/>",
      mode = "n",
      options = { desc = "Toggle comment (normal)" },
    },
    {
      action = "<PLUG>(comment_toggle_linewise_visual)",
      key = "<C-/>",
      mode = "x",
      options = { desc = "Toggle comment (visual)" },
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
      action = function() Snacks.picker.lsp_definitions() end,
      key = "]]",
      mode = "n",
      options = { desc = "Search definitions" },
    },
    {
      action = function() Snacks.picker.lsp_references() end,
      key = "[[",
      mode = "n",
      options = { desc = "Search references" },
    },
    {
      action = function() Snacks.picker.grep() end,
      key = "<C-f>",
      mode = "n",
      options = { desc = "Fuzzy find file contents" },
    },
    {
      action = function() Snacks.picker.buffers() end,
      key = "<C-b>",
      mode = "n",
      options = { desc = "Search through current buffers" },
    },
    {
      action = function() Snacks.picker.files() end,
      key = "<C-o>",
      mode = "n",
      options = { desc = "Find files by name" },
    },
    {
      action = function() Snacks.picker.diagnostics() end,
      key = "<C-q>",
      mode = "n",
      options = { desc = "Show diagnostics" },
    },
    {
      action = function() Snacks.picker.keymaps() end,
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

require("overseer").setup({
  strategy = "terminal",
  task_list = {
    direction = "bottom",
    bindings = {
      ["<C-h>"] = "<CMD>wincmd h<CR>",
      ["<C-j>"] = "<CMD>wincmd j<CR>",
      ["<C-k>"] = "<CMD>wincmd k<CR>",
      ["<C-l>"] = "<CMD>wincmd l<CR>",
    },
  },
})

require("dressing").setup({
  input = {
    start_mode = "normal",
  },
})

require("treesj").setup({
  -- Override default keymaps since it overrides <Leader>s
  use_default_keymaps = false,
  -- Stop stopping me from being stupid (default is 120)
  max_join_length = 1200,
})

-- package.path = package.path .. ";" .. "/Users/aaronpierce/.config/nvim/?.lua"
require("notes")
require("terminals")

local resession = require("resession")
local overseer = require("overseer")

local set_alacritty_window_name = function(name)
  local window_id = os.getenv("ALACRITTY_WINDOW_ID")

  local rename_command = string.format('alacritty msg config --window-id "%s" "window.title=\'%s\'"', window_id, name)

  os.execute(rename_command)
end

resession.setup({
  autosave = {
    enabled = true,
    interval = 240,
    notify = true,
  },
  extensions = {
    overseer = {
      unique = true,
      status = "RUNNING",
    },
  },
})

vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
  pattern = { "*.json" },
  callback = function()
    vim.opt.conceallevel = 0
  end,
})

vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    -- Reset the name whenever leaving the session
    local pokemon_name = os.getenv("CURRENT_POKEMON")
    set_alacritty_window_name(pokemon_name)
  end,
})

resession.add_hook("pre_load", function()
  -- Save the current session before starting to switch
  resession.save(vim.fn.getcwd(), { dir = "dirsession" })

  -- Dispose of all the running tasks in the current session
  for _, task in ipairs(overseer.list_tasks({})) do
    task:dispose(true)
  end

  -- Dispose of all the remaining terminal buffers
  local bufs = vim.api.nvim_list_bufs()
  for _, buf in ipairs(bufs) do
    if vim.api.nvim_get_option_value("buftype", { buf = buf }) == "terminal" then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
end)

resession.add_hook("post_load", function()
  local function get_cwd_as_name()
    local dir = vim.fn.getcwd(0)
    return dir:gsub("[^A-Za-z0-9]", "_")
  end

  overseer.load_task_bundle(get_cwd_as_name(), { ignore_missing = true })

  local bufs = vim.api.nvim_list_bufs()
  for _, buf in ipairs(bufs) do
    local line_count = vim.api.nvim_buf_line_count(buf)

    if line_count <= 1 then
      vim.api.nvim_buf_delete(buf, { force = true })

      local message = string.format("Closed empty buffer %s", buf)
      vim.print(message)
    end
  end

  -- Rename Alacritty to the session name
  local session_path = vim.split(vim.fn.getcwd(), "/")
  local session_name = table.remove(session_path)

  set_alacritty_window_name(session_name)
end)

require("flatten").setup({
  window = {
    open = "split",
  },
})

require("grug-far").setup()
require("tiny-inline-diagnostic").setup({
  preset = "ghost",

  options = {
    multiline = {
      enabled = true,
      always_show = true,
    },
  },
})

require("eagle").setup({
  keyboard_mode = true,
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
require("octo").setup({
  picker = "fzf-lua",
  picker_config = {
    use_emojis = true,
  },
})

return {
  "obsidian-nvim/obsidian.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  ft = "markdown",
  opts = {
    legacy_commands = false,
    workspaces = {
      {
        name = "Latte",
        path = "~/Documents/Latte",
      },
    },
    daily_notes = { date_format = "%Y/%m/%d %B, %Y", template = "Daily.md" },
    open_notes_in = "current",
    templates = { subdir = "~/Documents/Latte/Templates" },
    frontmatter = {
      enabled = false,
    },
    ui = {
      checkboxes = {
        [" "] = { char = " ", hl_group = "ObsidianTodo", order = 100 },
        ["~"] = { char = "~", hl_group = "ObsidianTilde", order = 200 },
        ["x"] = { char = "x", hl_group = "ObsidianDone", order = 300 },
      },
      enable = false,
    },
    follow_url_func = function(url)
      local is_darwin = vim.fn.has("macunix") == 1

      if is_darwin then
        vim.fn.jobstart({ "open", url })
      end

      if not is_darwin then
        vim.fn.jobstart({ "xdg-open", url })
      end
    end,
  },
}

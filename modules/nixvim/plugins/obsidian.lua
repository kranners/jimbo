local fzf_lua = require("fzf-lua")

local home = os.getenv("HOME")
local latte_root = vim.fn.resolve(home .. "/Documents/Latte")
local frappuccino_root = vim.fn.resolve(latte_root .. "/frappuccino/docs")
local stack_root = vim.fn.resolve(latte_root .. "/Stack")

local daily_template_path = vim.fn.resolve(latte_root .. "/Templates/Daily.md")
local weekly_template_path = vim.fn.resolve(latte_root .. "/Templates/Weekly.md")

local util = require("obsidian.util")

-- local smart_action_across_vaults = function()
--   local current_line = vim.api.nvim_get_current_line()
--   local start_pos, end_pos, link_type = util.cursor_on_markdown_link(current_line, nil)
--
--   if link_type == "Wiki" then
--     local link_location = string.sub(current_line, start_pos + 2, end_pos - 2)
--
--     for _, search_dir in ipairs({ latte_root, frappuccino_root, stack_root }) do
--       local note_path = string.format("%s/%s.md", search_dir, link_location)
--       if vim.fn.filereadable(note_path) == 1 then
--         return vim.cmd.edit(note_path)
--       end
--     end
--   end
--
--   return util.smart_action()
-- end

require("obsidian").setup({
  daily_notes = { date_format = "%Y/%m/%d %B, %Y", template = "Daily.md" },
  open_notes_in = "current",
  templates = { subdir = latte_root .. "/Templates" },
  disable_frontmatter = true,
  ui = {
    checkboxes = {
      [" "] = { char = " ", hl_group = "ObsidianTodo", order = 100 },
      ["~"] = { char = "~", hl_group = "ObsidianTilde", order = 200 },
      ["x"] = { char = "x", hl_group = "ObsidianDone", order = 300 },
    },
    enable = false,
  },
  workspaces = {
    { name = "Latte",       path = latte_root },
    { name = "Frappuccino", path = frappuccino_root },
  },
  follow_url_func = function(url)
    vim.fn.jobstart({ "open", url })
  end,
  -- mappings = {
  --   ["<cr>"] = {
  --     action = smart_action_across_vaults,
  --   },
  -- },
})

local get_note_template_contents = function(title)
  return {
    "---",
    string.format("id: %s", title),
    string.format('date: "%s"', os.date("%d %B, %Y")),
    "---",
    "",
    string.format("# %s", title),
    "",
  }
end

local prompt_for_new_note = function()
  local win = vim.api.nvim_get_current_win()

  -- Otherwise, create a new note with a given title
  local title = util.input("Enter title", { completion = "file" })
  if title == "" or title == nil then
    vim.notify("Provide a title for the note")
    return
  end

  -- Open a new horizontal split and move into it
  local buf = vim.api.nvim_create_buf(false, false)
  vim.cmd('split')
  vim.cmd('wincmd j')
  vim.api.nvim_win_set_buf(win, buf)

  -- Open a new note in that buffer
  local new_filepath = string.format("%s/%s.md", stack_root, title)
  vim.cmd.edit(new_filepath)

  -- Append the template to the file
  local template = get_note_template_contents(title)
  vim.api.nvim_put(template, "l", false, true)

  -- Go into insert mode
  vim.api.nvim_feedkeys("i", "t", false)
end

local move_note_to_vault = function(file, vault)
  local basename = vim.fs.basename(file)
  local new_filepath = vault .. "/" .. basename
  local command = string.format('mv "%s" "%s"', file, new_filepath)

  vim.notify("Moved note to " .. new_filepath)
  os.execute(command)
end

local get_note_ripgrep_call = function(additional_path)
  return function(query)
    if not query or query == "" then
      return table.concat({
        "rg",
        ".",
        additional_path,
        "--sortr=created",
        "--files-with-matches",
      }, " ")
    end

    local trimmed_query = string.gsub(query, '%s+$', '')
    local query_as_words = vim.split(trimmed_query, "%s")

    local query_words_with_wildcards = table.concat(query_as_words, ".*")

    return table.concat({
      "rg",
      additional_path,
      "--smart-case",
      "--column",
      "--no-heading",
      "--color=always",
      "--max-columns=4096",
      "--sortr=created",
      "--files-with-matches",
      "--multiline",
      "--multiline-dotall",
      "-e",
      string.format("'%s'", query_words_with_wildcards),
    }, " ")
  end
end

local get_fzf_note_actions = function(note_path_prefix)
  local for_each_note = function(callback)
    return function(selected_notes)
      for _, note in ipairs(selected_notes) do
        callback(
          string.format("%s/%s", note_path_prefix, note)
        )
      end
    end
  end

  local delete = function(note)
    os.execute(string.format('rm "%s"', note))
    vim.notify("Deleted note " .. note)
  end

  local archive = function(note)
    move_note_to_vault(note, latte_root)
  end

  local publish = function(note)
    move_note_to_vault(note, frappuccino_root)
  end

  return {
    ["default"] = fzf_lua.actions.file_edit,
    ["ctrl-d"] = { fn = for_each_note(delete), reload = true },
    ["ctrl-e"] = { fn = for_each_note(archive), reload = true },
    ["ctrl-p"] = { fn = for_each_note(publish), reload = true },
  }
end

local note_fzf_live_options = {
  fzf_opts = {
    ["--multi"] = true,
  },
  preview = "bat --color=always --theme='zenburn' --style=numbers {}",
  file_icons = false,
  git_icons = false,
  exec_empty_query = true,
}

local stack_notes = function()
  fzf_lua.fzf_live(
    get_note_ripgrep_call(""),
    vim.tbl_extend(
      "error",
      note_fzf_live_options,
      {
        prompt = "📚 ",
        winopts = { title = "Note Stack" },
        cwd = stack_root,
        actions = get_fzf_note_actions(stack_root),
      }
    )
  )
end

local all_notes = function()
  fzf_lua.fzf_live(
    get_note_ripgrep_call(latte_root .. " " .. frappuccino_root),
    vim.tbl_extend(
      "error",
      note_fzf_live_options,
      {
        prompt = "🏫 ",
        winopts = { title = "All Notes" },
        cwd = latte_root,
        actions = get_fzf_note_actions(""),
      }
    )
  )
end

local open_daily = function()
  -- Open the daily note path
  local daily_note_path = string.format(
    "%s/%s.md",
    latte_root,
    os.date("%Y/%m/%d %B, %Y")
  )

  vim.cmd.edit(daily_note_path)

  -- If we have nothing in there, then add the Daily template.
  local line_count = vim.api.nvim_buf_line_count(0)

  if line_count < 2 then
    local template = get_note_template_contents(os.date("%d %B, %Y"))
    vim.api.nvim_put(template, "l", false, true)

    vim.cmd.read(daily_template_path)
  end
end

local open_weekly = function()
  local week_num = math.floor(os.date("*t").yday / 7)
  local weekly_note_path = string.format(
    "%s/%s/Week %s.md",
    latte_root,
    os.date("%Y"),
    week_num
  )

  vim.cmd.edit(weekly_note_path)

  -- If we have nothing in there, then add the Weekly template.
  local line_count = vim.api.nvim_buf_line_count(0)

  if line_count < 2 then
    local template = get_note_template_contents("Week " .. week_num)
    vim.api.nvim_put(template, "l", false, true)

    vim.cmd.read(weekly_template_path)
  end
end

vim.keymap.set("n", "<Tab>", prompt_for_new_note)
vim.keymap.set("n", "<C-Tab>", stack_notes)
vim.keymap.set("n", "<Leader><Tab>", all_notes)
vim.keymap.set("n", "<Leader>d", open_daily)
vim.keymap.set("n", "<Leader>D", open_weekly)

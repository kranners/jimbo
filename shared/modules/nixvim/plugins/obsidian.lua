local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local home = os.getenv("HOME")

local latte_root = vim.fn.resolve(home .. "/Documents/Latte")
local frappuccino_root = vim.fn.resolve(home .. "/workspace/frappuccino/docs")
local stack_root = vim.fn.resolve(latte_root .. "/Stack")

require("obsidian").setup({
  daily_notes = { date_format = "%Y/%m/%d %B, %Y", template = "Daily.md" },
  open_notes_in = "current",
  templates = { subdir = latte_root .. "/Templates" },
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
})

local client = require("obsidian").get_client({ dir = latte_root })
local util = require("obsidian.util")

local prompt_for_new_note = function()
  -- If we are currently in a floating window, just close that instead
  local win = vim.api.nvim_get_current_win()
  local win_config = vim.api.nvim_win_get_config(win)

  local floating = win_config.relative == "editor"
  if floating then
    vim.api.nvim_buf_delete(vim.api.nvim_win_get_buf(win), { force = true })
    return
  end

  -- Otherwise, create a new note with a given title
  local title = util.input("Enter title", { completion = "file" })
  if title == "" or title == nil then
    vim.notify("Provide a title for the note")
    return
  end

  local note = client:create_note({ title = title, no_write = true, dir = stack_root })

  local width = math.ceil(math.min(150, vim.o.columns * 0.8))
  local height = math.ceil(math.min(35, vim.o.lines * 0.5))
  local row = math.ceil(vim.o.lines - height) * 0.5 - 1
  local col = math.ceil(vim.o.columns - width) * 0.5 - 1

  local float_config = {
    width = width,
    height = height,
    row = row,
    col = col,
    relative = "editor",
    border = "rounded",
  }

  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_open_win(buf, true, float_config)

  client:open_note(note, { sync = true })
  client:write_note_to_buffer(note)
end

local daily_note_path = string.format(
  "%s/%s.md",
  latte_root,
  os.date("%Y/%m/%d %B, %Y")
)

local entry_maker = function(line)
  local note = client:resolve_note(line)

  local path = vim.split(line, "/")
  local name = path[#path]

  return {
    display = note.aliases[1] or name or line,
    ordinal = line,
    value = line,
  }
end

local note_grepper = function(prompt)
  if not prompt or prompt == "" then
    return {
      "rg",
      ".*",
      stack_root,
      daily_note_path,
      "--files-with-matches",
    }
  end

  local prompt_words = vim.split(prompt, "%s")
  local prompt_as_rg_and = table.concat(prompt_words, ".*")

  return {
    "rg",
    "--ignore-case",
    "--multiline",
    "--multiline-dotall",
    prompt_as_rg_and,
    stack_root,
    daily_note_path,
    "--files-with-matches",
  }
end

local all_note_grepper = function(prompt)
  if not prompt or prompt == "" then
    return {
      "rg",
      ".*",
      latte_root,
      frappuccino_root,
      "--files-with-matches",
    }
  end

  local prompt_words = vim.split(prompt, "%s")
  local prompt_as_rg_and = table.concat(prompt_words, ".*")

  return {
    "rg",
    "--ignore-case",
    "--multiline",
    "--multiline-dotall",
    prompt_as_rg_and,
    latte_root,
    frappuccino_root,
    "--files-with-matches",
  }
end

local refresh_picker = function(prompt_bufnr)
  local picker = action_state.get_current_picker(prompt_bufnr)
  picker:refresh(nil, { reset_prompt = false })
end

local get_selected_filepath = function()
  return action_state.get_selected_entry().value
end

local move_note = function(new_filepath)
  local filepath = get_selected_filepath()
  local command = string.format('mv "%s" "%s"', filepath, new_filepath)

  vim.notify("Moved note to " .. new_filepath)
  os.execute(command)
end

local move_note_to_vault = function(vault)
  local filepath = get_selected_filepath()
  local note = client:resolve_note(filepath)

  move_note(vault .. "/" .. note.aliases[1] .. ".md")
end

local delete_note = function(prompt_bufnr)
  local filepath = get_selected_filepath()
  os.execute(string.format('rm "%s"', filepath))
  vim.notify("Deleted note " .. filepath)
  refresh_picker(prompt_bufnr)
end

local archive_note = function(prompt_bufnr)
  move_note_to_vault(latte_root)
  refresh_picker(prompt_bufnr)
end

local publish_note = function(prompt_bufnr)
  move_note_to_vault(frappuccino_root)
  refresh_picker(prompt_bufnr)
end

local make_note_daily = function(prompt_bufnr)
  move_note(daily_note_path)
  refresh_picker(prompt_bufnr)
end

local stack_notes = function(opts)
  opts = opts or {}

  local picker = pickers.new(opts, {
    prompt_title = "Note Stack",
    prompt_prefix = "📚 ",
    finder = finders.new_job(
      note_grepper,
      entry_maker
    ),
    previewer = conf.file_previewer(opts),
    attach_mappings = function(_, map)
      map({ "i", "n" }, "<C-d>", delete_note)
      map({ "i", "n" }, "<C-e>", archive_note)
      map({ "i", "n" }, "<C-p>", publish_note)
      map({ "i", "n" }, "<C-m>", make_note_daily)
      map({ "i", "n" }, "<C-Space>", actions.delete_buffer)
      map({ "i", "n" }, "<CR>", actions.file_edit)
      return true
    end
  })

  picker:find()
end

local all_notes = function(opts)
  opts = opts or {}

  local picker = pickers.new(opts, {
    prompt_title = "All Notes",
    prompt_prefix = "🏫 ",
    finder = finders.new_job(
      all_note_grepper,
      entry_maker
    ),
    previewer = conf.file_previewer(opts),
    attach_mappings = function(_, map)
      map({ "i", "n" }, "<C-d>", delete_note)
      map({ "i", "n" }, "<C-e>", archive_note)
      map({ "i", "n" }, "<C-p>", publish_note)
      map({ "i", "n" }, "<C-m>", make_note_daily)
      map({ "i", "n" }, "<C-Space>", actions.delete_buffer)
      map({ "i", "n" }, "<CR>", actions.file_edit)
      return true
    end
  })

  picker:find()
end

vim.keymap.set("n", "<Tab>", prompt_for_new_note)
vim.keymap.set("n", "<C-Tab>", stack_notes)
vim.keymap.set("n", "<Leader><Tab>", all_notes)

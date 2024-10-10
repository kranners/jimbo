local fzf_lua = require("fzf-lua")

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
  follow_url_func = function(url)
    vim.fn.jobstart({ "open", url })
  end
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

  local note = client:create_note({
    title = title,
    no_write = true,
    dir = stack_root,
    id = title
  })

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

local move_note_to_vault = function(file, vault)
  local note = client:resolve_note(file)

  local note_title = note.aliases[1] or note.id
  local new_filepath = vault .. "/" .. note_title .. ".md"
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
  vim.cmd("e " .. latte_root)
  vim.cmd("ObsidianToday")
end

vim.keymap.set("n", "<Tab>", prompt_for_new_note)
vim.keymap.set("n", "<C-Tab>", stack_notes)
vim.keymap.set("n", "<Leader><Tab>", all_notes)
vim.keymap.set("n", "<Leader>d", open_daily)

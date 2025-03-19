local fzf_lua = require("fzf-lua")
local NotePreviewer = require("notes.previewer")
local actions = require("notes.actions")
local constants = require("notes.constants")

local M = {}

local get_rg_callback = function(cwd, cuts)
  return function(query)
    if not query or query == "" then
      return table.concat({
        "rg",
        cwd,
        "--sortr=accessed",
        "--files-with-matches",
        "-e .",
        "| cut -d '/' -f " .. cuts .. "-",
      }, " ")
    end

    local trimmed_query = string.gsub(query, '%s+$', '')
    local query_as_words = vim.split(trimmed_query, "%s")

    local query_words_with_wildcards = table.concat(query_as_words, ".*")
    return table.concat({
      "rg",
      cwd,
      "--smart-case",
      "--column",
      "--no-heading",
      "--color=always",
      "--max-columns=4096",
      "--sortr=accessed",
      "--files-with-matches",
      "--multiline",
      "--multiline-dotall",
      "-e",
      string.format("'%s'", query_words_with_wildcards),
      "| cut -d '/' -f " .. cuts .. "-",
    }, " ")
  end
end

local on_close_without_select = function()
  local last_query = fzf_lua.get_last_query()

  if last_query ~= "" then
    local search_history_note_path = constants.latte_root .. "/Search History.md"
    local date_and_time = os.date("%c")

    local append_command = string.format(
      "echo '%s - %s' >> '%s'",
      date_and_time,
      last_query,
      search_history_note_path
    )

    os.execute(append_command)
  end

  fzf_lua.hide()
end

M.search_all_notes = function()
  fzf_lua.fzf_live(
    get_rg_callback(constants.latte_root, "6"),
    {
      fzf_opts = {
        ["--multi"] = true,
      },
      exec_empty_query = true,
      cwd = constants.latte_root,
      prompt = "🏫 ",
      winopts = {
        title = "All Notes",
        on_create = function(e)
          vim.keymap.set(
            { "t", "n" },
            "<Esc>",
            on_close_without_select,
            { buffer = e.bufnr, nowait = true }
          )
        end
      },
      previewer = NotePreviewer,
      actions = actions.get_actions_table(constants.latte_root),
    })
end

M.stack_notes = function()
  fzf_lua.fzf_live(
    get_rg_callback(constants.stack_root, "7"),
    {
      fzf_opts = {
        ["--multi"] = true,
      },
      exec_empty_query = true,
      cwd = constants.stack_root,
      prompt = "📚 ",
      winopts = {
        title = "Stack Notes",
        on_create = function(e)
          vim.keymap.set(
            { "t", "n" },
            "<Esc>",
            fzf_lua.hide,
            { buffer = e.bufnr, nowait = true }
          )
        end
      },
      previewer = NotePreviewer,
      actions = actions.get_actions_table(constants.stack_root),
    })
end

return M

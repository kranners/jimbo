local fzf_lua = require("fzf-lua")
local NotePreviewer = require("previewer")
local actions = require("actions")
local constants = require("constants")

local M = {}

local get_rg_callback = function(cwd, cuts)
  return function(query)
    if not query or query == "" then
      return table.concat({
        "rg",
        cwd,
        "--sortr=modified",
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
      "--sortr=modified",
      "--files-with-matches",
      "--multiline",
      "--multiline-dotall",
      "-e",
      string.format("'%s'", query_words_with_wildcards),
      "| cut -d '/' -f " .. cuts .. "-",
    }, " ")
  end
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
      winopts = { title = "All Notes" },
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
      winopts = { title = "Stack Notes" },
      previewer = NotePreviewer,
      actions = actions.get_actions_table(constants.stack_root),
    })
end

return M

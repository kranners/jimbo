local fzf_lua = require("fzf-lua")
local NotePreviewer = require("previewer")
local actions = require("actions")
local constants = require("constants")

local M = {}

local get_rg_call = function(query)
  -- vim.print("query: " .. query)

  if not query or query == "" then
    return table.concat({
      "fzf",
      "--sortr=created",
      "--files-with-matches",
    }, " ")
  end

  local trimmed_query = string.gsub(query, '%s+$', '')
  local query_as_words = vim.split(trimmed_query, "%s")

  local query_words_with_wildcards = table.concat(query_as_words, ".*")
  local value = table.concat({
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

  return value
end

local fn_transform = function(line)
  local line_dirname = vim.fs.dirname(line)
  local line_trimmed = vim.trim(vim.fs.basename(line))
  return fzf_lua.make_entry.file(line_trimmed, { cwd = line_dirname })
end

local note_fzf_live_options = {
  fzf_opts = {
    ["--multi"] = true,
  },
  previewer = NotePreviewer,
  file_icons = false,
  git_icons = false,
  exec_empty_query = true,
  actions = actions,
  fn_transform = fn_transform,
}

M.stack_notes = function()
  fzf_lua.fzf_live(
    get_rg_call,
    vim.tbl_extend(
      "error",
      note_fzf_live_options,
      {
        prompt = "📚 ",
        winopts = { title = "Note Stack" },
        cwd = constants.stack_root,
      }
    )
  )
end


M.search_all_notes = function()
  fzf_lua.live_grep({
    cwd = constants.latte_root,
    prompt = "🏫 ",
    previewer = NotePreviewer,
    exec_empty_query = true,
    actions = actions,
    rg_opts = "--smart-case" ..
        " --column" ..
        " --no-heading" ..
        " --color=always" ..
        " --max-columns=4096" ..
        " --sortr=created" ..
        " --files-with-matches" ..
        " --multiline" ..
        " --multiline-dotall",
  })
end

return M

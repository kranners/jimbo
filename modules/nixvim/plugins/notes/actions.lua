local constants = require("constants")
local fzf_lua = require("fzf-lua")

local move_note_to_vault = function(file, vault)
  local basename = vim.fs.basename(file)
  local new_filepath = vault .. "/" .. basename
  local command = string.format('mv "%s" "%s"', file, new_filepath)

  vim.notify("Moved note to " .. new_filepath)
  os.execute(command)
end

local for_each_note = function(callback)
  return function(selected_notes)
    for _, note in ipairs(selected_notes) do
      callback(note)
    end
  end
end

local delete = function(note)
  os.execute(string.format('rm "%s"', note))
  vim.notify("Deleted note " .. note)
end

local archive = function(note)
  move_note_to_vault(note, constants.latte_root)
end

local publish = function(note)
  move_note_to_vault(note, constants.frappuccino_root)
end

return {
  ["default"] = fzf_lua.actions.file_edit,
  ["ctrl-d"] = { fn = for_each_note(delete), reload = true },
  ["ctrl-e"] = { fn = for_each_note(archive), reload = true },
  ["ctrl-p"] = { fn = for_each_note(publish), reload = true },
}

local resession = require('resession')
local overseer = require('overseer')

local set_alacritty_window_name = function(name)
  local window_id = os.getenv("ALACRITTY_WINDOW_ID")

  local rename_command = string.format(
    'alacritty msg config --window-id "%s" "window.title=\'%s\'"',
    window_id,
    name
  )

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
  }
})

vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    -- Reset the name whenever leaving the session
    local pokemon_name = os.getenv("CURRENT_POKEMON")
    set_alacritty_window_name(pokemon_name)
  end
})

resession.add_hook(
  "pre_load",
  function()
    -- Save the current session before starting to switch
    resession.save(vim.fn.getcwd(), { dir = "dirsession" })

    -- Dispose of all the running tasks in the current session
    for _, task in ipairs(overseer.list_tasks({})) do
      task:dispose(true)
    end

    -- Dispose of all the remaining terminal buffers
    local bufs = vim.api.nvim_list_bufs()
    for _, buf in ipairs(bufs) do
      local buftype = vim.api.nvim_buf_get_option(buf, 'buftype')

      if buftype == 'terminal' then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
  end
)

resession.add_hook(
  "post_load",
  function()
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

    -- Rename Alacritty to include the session name
    local session_path = vim.split(vim.fn.getcwd(), "/")
    local session_name = table.remove(session_path)

    local pokemon_name = os.getenv("CURRENT_POKEMON")
    local window_name = string.format("%s (%s)", session_name, pokemon_name)

    set_alacritty_window_name(window_name)
  end
)

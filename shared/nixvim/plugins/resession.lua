local resession = require('resession')
local overseer = require('overseer')

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
  end
)

local telescope = require('telescope')
telescope.setup({
  extensions = {
    resession = {
      prompt_title = "Find Sessions",
      dir = "dirsession",
    },
  },
})

local resession = require('resession')
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
    local overseer = require('overseer')

    for _, task in ipairs(overseer.list_tasks({})) do
      task:dispose(true)
    end
  end
)

resession.add_hook(
  "post_load",
  function()
    local overseer = require('overseer')

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

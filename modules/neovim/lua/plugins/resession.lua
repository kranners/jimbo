return {
  'stevearc/resession.nvim',
  opts = {
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
    },
  },
  config = function(_, opts)
    local resession = require("resession")
    local overseer = require("overseer")

    resession.setup(opts)

    resession.add_hook("pre_load", function()
      -- Save the current session before starting to switch
      resession.save(vim.fn.getcwd(), { dir = "dirsession" })

      -- Dispose of all the running tasks in the current session
      for _, task in ipairs(overseer.list_tasks({})) do
        task:dispose(true)
      end

      -- Dispose of all the remaining terminal buffers
      local bufs = vim.api.nvim_list_bufs()
      for _, buf in ipairs(bufs) do
        if vim.api.nvim_get_option_value("buftype", { buf = buf }) == "terminal" then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end)

    resession.add_hook("post_load", function()
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
    end)
  end
}

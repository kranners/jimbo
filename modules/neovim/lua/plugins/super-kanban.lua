return {
  "hasansujon786/super-kanban.nvim",
  dependencies = {
    "folke/snacks.nvim",
  },
  opts = {
    markdown = {
      notes_dir = "~/Documents/Latte/Kanban/tasks",
      default_template = {
        "## Todo\n",
        "## In progress\n",
        "## Done\n",
      },
    },
    mappings = {
      ["H"] = "move_left",
      ["J"] = "move_down",
      ["K"] = "move_up",
      ["L"] = "move_right",

      ["h"] = "jump_left",
      ["j"] = "jump_down",
      ["k"] = "jump_up",
      ["l"] = "jump_right",

      ["o"] = "create_card_after",
    },
  },
  keys = {
    {
      "!",
      function()
        local home = os.getenv("HOME")
        local board_root_path = home .. "/Documents/Latte/Kanban"
        os.execute("mkdir -p " .. board_root_path)
        os.execute("mkdir -p " .. board_root_path .. "/tasks")

        local working_directory = os.getenv("PWD")
        local project_name_handle = io.popen("basename " .. working_directory)

        if project_name_handle == nil then
          return
        end

        local project_name = vim.trim(project_name_handle:read("*a"))
        project_name_handle:close()

        local project_board_path = string.format("%s/%s.md", board_root_path, project_name)

        if vim.uv.fs_stat(project_board_path) ~= nil then
          vim.print("it exists")
          return require("super-kanban").open(project_board_path)
        end

        require("super-kanban").create(project_board_path)
      end,
    },
  },
}

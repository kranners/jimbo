{
  programs.nixvim = {
    plugins.obsidian = {
      enable = true;

      settings = {
        workspaces = [
          {
            name = "Latte";
            path = "~/Documents/Latte";
          }
          {
            name = "Frappuccino";
            path = "~/workspace/frappuccino/docs";
          }
        ];

        open_notes_in = "current";

        templates.subdir = "Templates";

        daily_notes = {
          # See: https://www.lua.org/pil/22.1.html
          date_format = "%Y/%m/%d %B, %Y";
          template = "Daily.md";
        };

        follow_url_func = ''
          function(url)
            vim.fn.jobstart({ "open", url })
          end
        '';
      };
    };

    keymaps = [
      {
        key = "<Tab>";
        action.__raw = ''
          function()
            local client = require("obsidian").get_client()
            local util = require("obsidian.util")

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

            local note = client:create_note({ title = title, no_write = true, dir = "Stack" })

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
        '';
        options = { desc = "Open new note"; };
        mode = "n";
      }

      {
        key = "<Leader><Tab>";
        action = "<CMD>ObsidianQuickSwitch<CR>";
        options = { desc = "Open Obsidian note finder"; };
        mode = "n";
      }
    ];

    # See: https://github.com/epwalsh/obsidian.nvim/issues/286
    opts.conceallevel = 1;
  };
}

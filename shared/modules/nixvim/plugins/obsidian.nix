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

        ui = {
          enable = false;

          checkboxes = {
            " " = {
              char = " ";
              hl_group = "ObsidianTodo";
            };
            "~" = {
              char = "~";
              hl_group = "ObsidianTilde";
            };
            x = {
              char = "x";
              hl_group = "ObsidianDone";
            };
          };
        };
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
        action.__raw = ''
          function()
            local pickers = require("telescope.pickers")
            local finders = require("telescope.finders")
            local conf = require("telescope.config").values
            local actions = require("telescope.actions")
            local action_state = require("telescope.actions.state")

            local obsidian_client = require("obsidian").get_client()
            local vault_root = obsidian_client:vault_root().filename
            local stack_root = vim.fn.resolve(vault_root .. "/Stack")

            local frappuccino_root = "/Users/aaronpierce/workspace/frappuccino/docs";

            local entry_maker = function(line)
              local note = obsidian_client:resolve_note(line)

              return {
                display = note.aliases[1],
                ordinal = line,
                value = line,
              }
            end

            local note_grepper = function(prompt)
              if not prompt or prompt == "" then
                return { "find", stack_root, "-type", "f" }
              end

              local prompt_words = vim.split(prompt, "%s")
              local prompt_as_rg_and = table.concat(prompt_words, ".*")

              return {
                "rg",
                "--ignore-case",
                "--multiline",
                "--multiline-dotall",
                prompt_as_rg_and,
                stack_root,
                "--files-with-matches",
              }
            end

            local refresh_picker = function(prompt_bufnr)
              local picker = action_state.get_current_picker(prompt_bufnr)
              picker:refresh(nil, { reset_prompt = false })
            end

            local move_note = function(new_filepath)
              local filepath = action_state.get_selected_entry().value
              local command = "mv " .. filepath .. ' "' .. new_filepath .. '"'
              os.execute(command)
            end

            local move_note_to_vault = function(vault)
              local filepath = action_state.get_selected_entry().value
              local note = obsidian_client:resolve_note(filepath)

              move_note(vault .. "/" .. note.aliases[1] .. ".md")
            end

            local delete_note = function(prompt_bufnr)
              local filepath = action_state.get_selected_entry().value
              os.execute("rm " .. filepath)

              refresh_picker(prompt_bufnr)
            end

            local archive_note = function(prompt_bufnr)
              move_note_to_vault(vault_root)
              refresh_picker(prompt_bufnr)
            end

            local publish_note = function(prompt_bufnr)
              move_note_to_vault(frappuccino_root)
              refresh_picker(prompt_bufnr)
            end

            local make_note_daily = function(prompt_bufnr)
              move_note(os.date("%Y/%m/%d %B, %Y") .. ".md")
              refresh_picker(prompt_bufnr)
            end

            local stack_notes = function(opts)
              opts = opts or {}

              local picker = pickers.new(opts, {
                prompt_title = "Note Stack",
                finder = finders.new_job(
                  note_grepper,
                  entry_maker
                ),
                previewer = conf.file_previewer(opts),
                attach_mappings = function(_, map)
                  map({ "i", "n" }, "<C-d>", delete_note)
                  map({ "i", "n" }, "<C-e>", archive_note)
                  map({ "i", "n" }, "<C-p>", publish_note)
                  map({ "i", "n" }, "<C-m>", make_note_daily)
                  map({ "i", "n" }, "<CR>", actions.file_edit)
                  return true
                end
              })

              picker:find()
            end

            stack_notes()
          end
        '';
        options = { desc = "Open note stack"; };
        mode = "n";
      }
    ];

    # See: https://github.com/epwalsh/obsidian.nvim/issues/286
    opts.conceallevel = 1;
  };
}

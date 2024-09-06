{ pkgs, ... }:
let
  # FIXME: yucky, ew
  inherit (pkgs.hostPlatform) isDarwin;

  DARWIN_LATTE_ROOT = "/Users/aaronpierce/Documents/Latte";
  DARWIN_FRAPPUCCINO_ROOT = "/Users/aaronpierce/workspace/frappuccino/docs";

  NIXOS_LATTE_ROOT = "/home/aaron/Documents/Latte";
  NIXOS_FRAPPUCCINO_ROOT = "/home/aaron/workspace/frappuccino/docs";

  LATTE_ROOT = if isDarwin then DARWIN_LATTE_ROOT else NIXOS_LATTE_ROOT;
  FRAPPUCCINO_ROOT = if isDarwin then DARWIN_FRAPPUCCINO_ROOT else NIXOS_FRAPPUCCINO_ROOT;

  STACK_DIR_NAME = "Stack";
in
{
  programs.nixvim = {
    plugins.obsidian = {
      enable = true;

      settings = {
        workspaces = [
          {
            name = "Latte";
            path = LATTE_ROOT;
          }
          {
            name = "Frappuccino";
            path = FRAPPUCCINO_ROOT;
          }
        ];

        open_notes_in = "current";

        templates.subdir = "Templates";

        daily_notes = {
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

            local note = client:create_note({ title = title, no_write = true, dir = "${STACK_DIR_NAME}" })

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
                return { "find", "${LATTE_ROOT}/${STACK_DIR_NAME}", "-type", "f" }
              end

              local prompt_words = vim.split(prompt, "%s")
              local prompt_as_rg_and = table.concat(prompt_words, ".*")

              return {
                "rg",
                "--ignore-case",
                "--multiline",
                "--multiline-dotall",
                prompt_as_rg_and,
                "${LATTE_ROOT}/${STACK_DIR_NAME}",
                "--files-with-matches",
              }
            end

            local refresh_picker = function(prompt_bufnr)
              local picker = action_state.get_current_picker(prompt_bufnr)
              picker:refresh(nil, { reset_prompt = false })
            end

            local get_selected_filepath = function()
              return action_state.get_selected_entry().value
            end

            local move_note = function(new_filepath)
              local filepath = get_selected_filepath()
              local command = string.format('mv "%s" "%s"', filepath, new_filepath)

              vim.notify("Moved note to " .. new_filepath)
              os.execute(command)
            end

            local move_note_to_vault = function(vault)
              local filepath = get_selected_filepath()
              local note = obsidian_client:resolve_note(filepath)

              move_note(vault .. "/" .. note.aliases[1] .. ".md")
            end

            local delete_note = function(prompt_bufnr)
              local filepath = get_selected_filepath()
              os.execute("rm " .. filepath)
              vim.notify("Deleted note " .. filepath)
              refresh_picker(prompt_bufnr)
            end

            local archive_note = function(prompt_bufnr)
              move_note_to_vault("${LATTE_ROOT}")
              refresh_picker(prompt_bufnr)
            end

            local publish_note = function(prompt_bufnr)
              move_note_to_vault("${FRAPPUCCINO_ROOT}")
              refresh_picker(prompt_bufnr)
            end

            local make_note_daily = function(prompt_bufnr)
              local daily_note_path = string.format(
                "${LATTE_ROOT}/%s.md", 
                os.date("%Y/%m/%d %B, %Y")
              )

              move_note(daily_note_path)
              refresh_picker(prompt_bufnr)
            end

            local stack_notes = function(opts)
              opts = opts or {}

              local picker = pickers.new(opts, {
                prompt_title = "Note Stack",
                prompt_prefix = "📚 ",
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
                  map({ "i", "n" }, "<C-Space>", actions.delete_buffer)
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

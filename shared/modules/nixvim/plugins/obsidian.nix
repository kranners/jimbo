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

            if client.current_note(client) == nil then
                return vim.cmd("ObsidianToday")
            else
                return vim.cmd("e#")
            end
          end
        '';
        options = { desc = "Open Obsidian daily note"; };
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

{
  programs.nixvim.plugins = {
    noice = {
      enable = true;

      settings = {
        health.checker = false;

        views = {
          cmdline_popup = {
            filter_options = { };
            win_options = {
              winhighlight = "NormalFloat:NormalFloat,FloatBorder:FloatBorder";
            };
          };
        };

        routes = [
          {
            view = "notify";
            filter.event = "msg_showmode";
          }
        ];
      };
    };

    lualine = {
      enable = true;

      settings.sections.lualine_x = [
        {
          __raw = ''
            {
              function()
                local mode = require('noice').api.statusline.mode
                if mode.has() then
                  local content = mode.get()
                  if string.match(content, "^recording @%w$") then
                    return content
                  end
                end
                return ""
              end,
              color = { fg = "#ff9e64" }
            }
          '';
        }
      ];
    };
  };
}

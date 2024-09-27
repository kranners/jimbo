{
  programs.nixvim.plugins = {
    noice = {
      enable = true;

      health.checker = false;

      views = {
        cmdline_popup = {
          filter_options = { };
          win_options = {
            winhighlight = "NormalFloat:NormalFloat,FloatBorder:FloatBorder";
          };
        };
      };
    };
  };
}

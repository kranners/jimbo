{
  programs.nixvim.plugins = {
    noice = {
      enable = true;

      health.checker = false;

      views = {
        cmdline_popup = {
          border = {
            style = "none";
            padding = [ 2 3 ];
          };
          filter_options = { };
          win_options = {
            winhighlight = "NormalFloat:NormalFloat,FloatBorder:FloatBorder";
          };
        };
      };
    };
  };
}

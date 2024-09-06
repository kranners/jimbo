{
  programs.nixvim.plugins.firenvim = {
    enable = true;

    settings = {
      globalSettings = {
        alt = "all";
      };

      localSettings = {
        ".*" = {
          cmdline = "nvim";
          content = "text";
          priority = 0;
          selector = "textarea";
          takeover = "always";
        };

        ".*messenger.com.*" = { priority = 1; takeover = "never"; };
        ".*linear.app.*" = { priority = 1; takeover = "never"; };
      };
    };
  };
}

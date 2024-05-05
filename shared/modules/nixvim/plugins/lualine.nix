let
  filename-segment = {
    name = "filename";
    extraConfig = {
      path = 1;
    };
  };
in {
  programs.nixvim.plugins.lualine = {
    enable = true;
    winbar.lualine_a = [filename-segment];
    inactiveWinbar.lualine_a = [filename-segment];
  };
}

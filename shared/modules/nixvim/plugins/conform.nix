{
  programs.nixvim = {
    plugins.conform-nvim = {
      enable = true;

      settings = {
        format_on_save = {
          timeout_ms = 500;
          lsp_fallback = true;
        };

        formatters_by_fmt =
          let
            js-formatters = [ [ "eslint_d" "prettierd" ] ];
          in
          {
            javascript = js-formatters;
            javascriptreact = js-formatters;
            typescript = js-formatters;
            typescriptreact = js-formatters;
          };
      };

    };

    keymaps = [
      {
        key = "<Leader><Leader>";
        action = "<CMD>lua require('conform').format()<CR>";
        options = { desc = "Format document"; };
        mode = "n";
      }
    ];
  };
}

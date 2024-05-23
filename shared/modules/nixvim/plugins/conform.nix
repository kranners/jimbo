{
  programs.nixvim = {
    plugins.conform-nvim = {
      enable = true;

      formatOnSave = {
        timeoutMs = 500;
        lspFallback = true;
      };

      formattersByFt =
        let
          jsFormatters = [ [ "eslint_d" "prettierd" ] ];
        in
        {
          javascript = jsFormatters;
          javascriptreact = jsFormatters;
          typescript = jsFormatters;
          typescriptreact = jsFormatters;
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

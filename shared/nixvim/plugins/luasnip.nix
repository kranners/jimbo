{
  programs.nixvim.plugins = {
    luasnip.enable = true;
    cmp_luasnip.enable = true;

    cmp.settings.snippet.expand = ''
      function(args)
        require('luasnip').lsp_expand(args.body)
      end
    '';
  };
}

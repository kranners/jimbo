{ pkgs
, inputs
, ...
}: {
  programs.nixvim = {
    extraPlugins = with inputs.awesome-neovim-plugins.packages.${pkgs.system}; [
      goto-preview
    ];

    extraConfigLua = ''
      require('goto-preview').setup()
    '';

    keymaps = [
      {
        key = "]";
        action = "<CMD>lua require('goto-preview').goto_preview_definition()<CR>";
        options = { desc = "Preview declaration"; };
        mode = "n";
      }

      {
        key = "[";
        action = "<CMD>lua require('goto-preview').goto_preview_references()<CR>";
        options = { desc = "Preview references"; };
        mode = "n";
      }
    ];
  };
}

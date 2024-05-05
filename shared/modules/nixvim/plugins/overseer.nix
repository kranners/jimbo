{
  inputs,
  pkgs,
  ...
}: {
  programs.nixvim = {
    keymaps = [
      {
        key = "<BS>";
        action = "<CMD>OverseerRun<CR>";
        options = {desc = "Run task";};
        mode = "n";
      }

      {
        key = "<Leader><BS>";
        action = "<CMD>OverseerToggle<CR>";
        options = {desc = "Toggle task view";};
        mode = "n";
      }
    ];

    extraPlugins = with inputs.awesome-neovim-plugins.packages.${pkgs.system}; [
      overseer-nvim
      dressing-nvim
    ];

    extraConfigLua = ''
      require('overseer').setup({
      strategy = {
      "toggleterm",
      use_shell = true,
      open_on_start = false,
      hidden = true,
      }
      })

      require('dressing').setup()
    '';
  };
}

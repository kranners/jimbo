{
  programs.nixvim.plugins.render-markdown = {
    enable = true;

    settings = {
      preset = "obsidian";

      anti_conceal = {
        enabled = true;
      };
    };
  };
}

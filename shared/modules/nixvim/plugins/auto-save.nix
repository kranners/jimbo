{
  programs.nixvim.plugins.auto-save = {
    enable = true;

    # Only enable auto-save for Markdown files, this is mainly for Obsidian integration
    condition = ''
      function(buf)
        local modifiable = vim.fn.getbufvar(buf, "&modifiable")
        local filetype = vim.fn.getbufvar(buf, "&filetype")

        return modifiable == 1 and filetype == "markdown"
      end
    '';
  };
}

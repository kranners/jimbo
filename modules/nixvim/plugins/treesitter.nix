{
  programs.nixvim.plugins.treesitter = {
    enable = true;
    settings = {
      ensure_installed = [
        "javascript"
        "tsx"
        "typescript"
        "python"
        "lua"
        "luadoc"
        "markdown"
        "vim"
        "vimdoc"
        "nix"
        "bash"
        "css"
        "diff"
        "graphql"
        "json"
        "just"
        "kotlin"
        "java"
        "swift"
        "scss"
      ];

      highlight = {
        enable = true;
        additional_vim_regex_highlighting = false;
      };

      indent.enable = true;
    };
  };
}

{ pkgs, ... }:
let
  inlay-hint = pkgs.vimUtils.buildVimPlugin {
    pname = "inlay-hint";
    version = "2024-07-19";

    src = pkgs.fetchFromGitHub {
      owner = "felpafel";
      repo = "inlay-hint.nvim";
      rev = "bc6a00b7129218dc1478624bc5cb1c31b191a46b";
      hash = "sha256-qcUtZBuBqKfXLAb8cXq8WYsEBTdH3XzhHBloULapLiI=";
    };
  };
in
{
  programs.nixvim = {
    plugins.lsp = {
      enable = true;

      servers = {
        astro.enable = true;
        tsserver.enable = true;
        lua-ls.enable = true;
        jsonls.enable = true;
        html.enable = true;
        # FIXME: Remove this when not working with cooked ESLint
        # eslint.enable = true;
        pyright.enable = true;
        yamlls.enable = true;

        nixd = {
          enable = true;
          settings.formatting.command = [ "nixpkgs-fmt" ];
        };
      };
    };

    keymaps = [
      {
        key = "<Leader><CR>";
        action = "<CMD>lua vim.lsp.buf.code_action()<CR>";
        options = { desc = "Show code actions"; };
        mode = "n";
      }

      {
        key = "<Leader>r";
        action = "<CMD>lua vim.lsp.buf.rename()<CR>";
        options = { desc = "Rename symbol"; };
        mode = "n";
      }
    ];

    plugins.lsp.inlayHints = true;
    extraPlugins = [ inlay-hint ];
  };
}

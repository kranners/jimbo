{ config
, pkgs
, lib
, inputs
, ...
}:
let
  makeNixvim = inputs.nixvim.legacyPackages.${pkgs.system}.makeNixvim;

  nixvim = {
    opts = {
      number = true;
      relativenumber = true;

      shiftwidth = 2;
    };

    globals.mapleader = " ";

    colorschemes.catppuccin = {
      enable = true;

      settings = {
        flavour = "latte"; # UK English
        term_colors = true; # US English
        # Pick one, Catppuccin!!
      };
    };

    keymaps = [
      {
        action = "<cmd>lua require('oil').open()<cr>";
        key = "-";
        mode = "n";
        options = { desc = "View files"; };
      }

      {
        action = "<cmd>ToggleTerm direction=float<cr>";
        key = "=";
        mode = "n";
        options = { desc = "Toggle terminal"; };
      }

      { key = "<C-h>"; action = "<CMD>wincmd h <CR>"; options = { desc = "Focus window left"; }; mode = [ "t" "n" ]; }
      { key = "<C-j>"; action = "<CMD>wincmd j <CR>"; options = { desc = "Focus window down"; }; mode = [ "t" "n" ]; }
      { key = "<C-k>"; action = "<CMD>wincmd k <CR>"; options = { desc = "Focus window up"; }; mode = [ "t" "n" ]; }
      { key = "<C-l>"; action = "<CMD>wincmd l <CR>"; options = { desc = "Focus window right"; }; mode = [ "t" "n" ]; }

      { key = "<Left>"; action = "<CMD>vertical resize +1<CR>"; options = { desc = "Grow window left"; }; mode = "n"; }
      { key = "<Down>"; action = "<CMD>resize +1<CR>"; options = { desc = "Grow window down"; }; mode = "n"; }
      { key = "<Up>"; action = "<CMD>resize -1<CR>"; options = { desc = "Shrink window up"; }; mode = "n"; }
      { key = "<Right>"; action = "<CMD>vertical resize -1<CR>"; options = { desc = "Shrink window left"; }; mode = "n"; }

      {
        key = "<ESC>";
        action = "<CMD>nohlsearch<Bar>:echo<CR>";
        options = { desc = "Cancel search"; };
        mode = "n";
      }

      {
        key = "<C-t>";
        action = "<CMD>tabnew<CR>";
        options = { desc = "New tab"; };
        mode = "n";
      }

      {
        key = "<C-tab>";
        action = "<CMD>tabnext<CR>";
        options = { desc = "Next tab"; };
        mode = "n";
      }

      {
        key = "<C-s-tab>";
        action = "<CMD>tabprevious<CR>";
        options = { desc = "Previous tab"; };
        mode = "n";
      }

      {
        key = "<BS>";
        action = "<CMD>OverseerRun<CR>";
        options = { desc = "Run task"; };
        mode = "n";
      }

      {
        key = "<Leader><BS>";
        action = "<CMD>OverseerToggle<CR>";
        options = { desc = "Toggle task view"; };
        mode = "n";
      }

      {
        key = "<Leader>n";
        action = "<CMD>FocusSplitNicely<CR>";
        options = { desc = "Make a new split"; };
        mode = "n";
      }

      {
        key = "<ESC>";
        action = "<C-\\><C-n>";
        options = { desc = "Let me move"; };
        mode = "t";
      }

      {
        key = "<C-f>";
        action = "<CMD>Telescope live_grep<CR>";
        options = { desc = "Fuzzy find file contents"; };
        mode = "n";
      }

      {
        key = "<C-o>";
        action = "<CMD>Telescope find_files<CR>";
        options = { desc = "Find files by name"; };
        mode = "n";
      }
    ];

    plugins = {
      lualine.enable = true;
      telescope.enable = true;
      notify.enable = true;
      surround.enable = true;
      toggleterm.enable = true;
      nvim-autopairs.enable = true;
      rainbow-delimiters.enable = true;
      comment.enable = true;
    };

    extraPlugins = with inputs.awesome-neovim-plugins.packages.${pkgs.system}; [ overseer-nvim dressing-nvim focus-nvim ];

    extraConfigLua = ''
      require('overseer').setup({
      -- Commenting out as currently leaves tasks in running state
      -- strategy = {
      -- "toggleterm",
      -- use_shell = true,
      -- quit_on_exit = "always",
      -- open_on_start = false,
      -- hidden = true,
      -- }
      })

      require('dressing').setup()

      require('focus').setup()
    '';

    plugins.treesitter = {
      enable = true;
      # indent = true;
    };

    plugins.cmp = {
      enable = true;

      cmdline = {
        "/" = {
          mapping = {
            __raw = "cmp.mapping.preset.cmdline()";
          };
          sources = [{ name = "buffer"; }];
        };

        ":" = {
          mapping = {
            __raw = "cmp.mapping.preset.cmdline()";
          };
          sources = [
            { name = "path"; }
            {
              name = "cmdline";
              option = {
                ignore_cmds = [
                  "Man"
                  "!"
                ];
              };
            }
          ];
        };
      };
    };

    plugins.oil = {
      enable = true;

      settings.keymaps = {
        "<C-l>" = false;
        "<C-h>" = false;
        "<C-c>" = false;
        "<C-r>" = "actions.refresh";
      };
    };

    plugins.lsp = {
      enable = true;
      servers = {
        astro.enable = true;
        tsserver.enable = true;
        lua-ls.enable = true;
        jsonls.enable = true;
        html.enable = true;
        eslint.enable = true;
        pyright.enable = true;
        yamlls.enable = true;
      };
    };

    plugins.lsp.servers.nixd = {
      enable = true;
      settings.formatting.command = "nixpkgs-fmt";
    };

    plugins.conform-nvim = {
      enable = true;
      formatOnSave = {
        timeoutMs = 500;
        lspFallback = true;
      };
    };
  };
in
{
  home.packages = [
    (makeNixvim nixvim)
    pkgs.nixpkgs-fmt
    pkgs.ripgrep
  ];
}
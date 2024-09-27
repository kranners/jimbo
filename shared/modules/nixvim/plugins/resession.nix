{ pkgs, inputs, ... }:
let
  resession = pkgs.vimUtils.buildVimPlugin {
    pname = "resession";
    version = "2024-08-20";
    src = inputs.resession;
    meta.homepage = "https://github.com/stevearc/resession.nvim";
  };
in
{
  programs.nixvim = {
    extraPlugins = [ resession ];
    extraConfigLua = builtins.readFile ./resession.lua;

    keymaps = [
      {
        key = "<Leader>S";
        action.__raw = ''
          function()
            require('resession').save(vim.fn.getcwd(), { dir = "dirsession" })
          end
        '';
        options = { desc = "Save session"; };
        mode = "n";
      }
    ];

    autoCmd = [
      {
        event = [ "VimEnter" ];
        nested = true;
        callback.__raw = ''
          function()
            -- Only load the session if nvim was started with no args
            if vim.fn.argc(-1) == 0 then
              -- Save these to a different directory, so our manual sessions don't get polluted
              require('resession').load(vim.fn.getcwd(), { dir = "dirsession", silence_errors = true })
            end
          end
        '';
      }

      {
        event = [ "VimLeavePre" ];
        nested = false;
        callback.__raw = ''
          function()
            require('resession').save(vim.fn.getcwd(), { dir = "dirsession" })
          end
        '';
      }
    ];
  };
}

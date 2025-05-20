local function bootstrap_pckr()
  local pckr_path = vim.fn.stdpath("data") .. "/pckr/pckr.nvim"

  if not (vim.uv or vim.loop).fs_stat(pckr_path) then
    vim.fn.system({
      'git',
      'clone',
      "--filter=blob:none",
      'https://github.com/lewis6991/pckr.nvim',
      pckr_path
    })
  end

  vim.opt.rtp:prepend(pckr_path)
end

bootstrap_pckr()

require('pckr').add {
  'stevearc/dressing.nvim',
  'nvim-lualine/lualine.nvim',
  'neovim/nvim-lspconfig',
  'hrsh7th/cmp-nvim-lsp',
  'scottmckendry/cyberdream.nvim',
  'folke/noice.nvim',
  'epwalsh/obsidian.nvim',
  'stevearc/oil.nvim/',
  'stevearc/resession.nvim',
  'rachartier/tiny-inline-diagnostic.nvim',
  'nvim-treesitter/nvim-treesitter',
  'Wansmer/treesj',
  'stevearc/overseer.nvim',
  'MeanderingProgrammer/render-markdown.nvim',
  'MagicDuck/grug-far.nvim',
  'ibhagwan/fzf-lua',
  'willothy/flatten.nvim',
  'soulis-1256/eagle.nvim',
  'stevearc/conform.nvim',
  'numToStr/Comment.nvim',
  'mistricky/codesnap.nvim',
  'hrsh7th/nvim-cmp',
  'romgrk/barbar.nvim',
  'nvim-tree/nvim-web-devicons',
  'kosayoda/nvim-lightbulb',
  'windwp/nvim-autopairs',
  'karb94/neoscroll.nvim',
  'MunifTanjim/nui.nvim',
  'lukas-reineke/indent-blankline.nvim',
  'lewis6991/gitsigns.nvim',
  'kylechui/nvim-surround',
  'tpope/vim-fugitive',
  'tpope/vim-rhubarb',
  'norcalli/nvim-colorizer.lua',
  'nvim-lua/plenary.nvim',
  'shortcuts/no-neck-pain.nvim',
  'pwntester/octo.nvim',
  'folke/snacks.nvim',
  'folke/zen-mode.nvim',
}

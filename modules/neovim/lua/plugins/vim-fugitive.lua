return {
	"tpope/vim-fugitive",
	keys = {
		{
			"<C-m>",
			"<CMD>.GBrowse!<CR>",
			mode = "n",
			desc = "Copy line permalink",
		},
		{
			"<Leader>m",
			"<CMD>.GBrowse<CR>",
			mode = "n",
			desc = "Open line permalink",
		},
	},
}

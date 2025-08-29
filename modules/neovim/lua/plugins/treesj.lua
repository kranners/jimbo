return {
	"Wansmer/treesj",
	opts = {
		-- Override default keymaps since it overrides <Leader>s
		use_default_keymaps = false,
		-- Stop stopping me from being stupid (default is 120)
		max_join_length = 1200,
	},
	keys = {
		{
			"<Leader>j",
			"<CMD>TSJJoin<CR>",
			mode = "n",
			desc = "Join object together",
		},
		{
			"<Leader>k",
			"<CMD>TSJSplit<CR>",
			mode = "n",
			desc = "Split object apart",
		},
	},
}

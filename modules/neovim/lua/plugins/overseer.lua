return {
	"stevearc/overseer.nvim",
	opts = {
		strategy = "terminal",
		task_list = {
			direction = "bottom",
			bindings = {
				["<C-h>"] = "<CMD>wincmd h<CR>",
				["<C-j>"] = "<CMD>wincmd j<CR>",
				["<C-k>"] = "<CMD>wincmd k<CR>",
				["<C-l>"] = "<CMD>wincmd l<CR>",
			},
		},
	},
	keys = {
		{
			"<BS>",
			"<CMD>OverseerRun<CR>",
			mode = "n",
			desc = "Run task",
		},
		{
			"<C-BS>",
			"<CMD>OverseerQuickAction open float<CR>",
			mode = "n",
			desc = "Open last task",
		},
		{
			"<Leader><BS>",
			"<CMD>OverseerToggle<CR>",
			mode = "n",
			desc = "Toggle task view",
		},
	},
}

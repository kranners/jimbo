local shared_fzf_opts = {
	["--ansi"] = true,
	["--info"] = "inline-right",
	["--height"] = "100%",
	["--layout"] = "reverse",
	["--border"] = "none",
	["--highlight-line"] = true,
	["--tiebreak"] = "begin",
}

local shared_fd_opts = "--type file "
	.. "--follow "
	.. "--no-ignore-vcs "
	.. "--hidden "
	.. "-E 'node_modules' "
	.. "-E '.direnv' "
	.. "-E '.git' "
	.. "-E '.env' "

return {
	{
		"elanmed/fzf-lua-frecency.nvim",
		dependencies = { "ibhagwan/fzf-lua" },
		opts = {
			fzf_opts = vim.tbl_extend("force", shared_fzf_opts, {
				["--no-sort"] = false,
			}),
			fd_opts = shared_fd_opts,
		},
	},
	{
		"ibhagwan/fzf-lua",
		opts = {
			"telescope",
			fzf_opts = shared_fzf_opts,
			fd_opts = shared_fd_opts,
		},
		keys = {
			{
				"]]",
				function()
					require("fzf-lua").lsp_definitions()
				end,
				desc = "Search definitions",
			},
			{
				"[[",
				function()
					require("fzf-lua").lsp_references()
				end,
				desc = "Search references",
			},
			{
				"<C-f>",
				function()
					require("fzf-lua").live_grep()
				end,
				desc = "Fuzzy find file contents",
			},
			{
				"<C-b>",
				function()
					require("fzf-lua").buffers()
				end,
				desc = "Search through current buffers",
			},
			{
				"<C-o>",
				function()
					require("fzf-lua-frecency").frecency({
						cwd_only = true,
					})
				end,
				desc = "Find files by name",
			},
		},
	},
}

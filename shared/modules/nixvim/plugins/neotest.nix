{
  programs.nixvim = {
    plugins.neotest = {
      enable = true;

      adapters = {
	jest.enable = true;
	# vitest.enable = true;
	# playwright.enable = true;
      };
    };

    keymaps = [
      {
        action = "<cmd>lua require('neotest').run.run(vim.fn.expand('%'))<cr>";
        key = "<Leader>tf";
        mode = "n";
        options = {desc = "Run current test file";};
      }

      {
        action = "<cmd>lua require('neotest').run.run()<cr>";
        key = "<Leader>ts";
        mode = "n";
        options = {desc = "Run current test";};
      }
    ];
  };
}

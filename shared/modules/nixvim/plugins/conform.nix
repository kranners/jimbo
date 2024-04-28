{
  programs.nixvim.plugins.conform-nvim = {
    enable = true;
    formatOnSave = {
      timeoutMs = 500;
      lspFallback = true;
    };
  };
}

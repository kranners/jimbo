{config, ...}: {
  programs.nixvim.plugins.startify = {
    enable = true;
    settings.session_dir = config.programs.nixvim.plugins.persistence.dir;
  };
}

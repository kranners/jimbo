{
  sharedHomeModule = {
    programs.ssh = {
      enable = true;

      matchBlocks = {
        "github.com" = {
          hostname = "github.com";
          user = "git";
          identityFile = "~/.ssh/id_rsa";
        };


        "*.dev.azure.com" = {
          host = "*.dev.azure.com";
          user = "git";
          identityFile = "~/.ssh/id_rsa_aaf";
        };
      };
    };
  };
}

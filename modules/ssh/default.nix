{
  sharedHomeModule = {
    programs.ssh = {
      enable = true;

      matchBlocks = {
        "github.com" = {
          hostname = "github.com";
          user = "git";
        };


        "*.dev.azure.com" = {
          host = "*.dev.azure.com";
          user = "git";
          identityFile = "~/.ssh/id_rsa_aaf";
        };
      };
    };
  };

  darwinHomeModule.programs.ssh.matchBlocks."github.com".identityFile = "~/.ssh/id_rsa";
  nixosHomeModule.programs.ssh.matchBlocks."github.com".identityFile = "~/.ssh/id_ed25519";
}

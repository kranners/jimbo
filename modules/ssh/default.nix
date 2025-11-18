{
  sharedHomeModule = {
    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;

      matchBlocks = {
        "github.com" = {
          hostname = "github.com";
          user = "git";
        };

        "*" = {
          forwardAgent = false;
          addKeysToAgent = "no";
          compression = false;
          serverAliveInterval = 120;
          serverAliveCountMax = 3;
          hashKnownHosts = false;
          userKnownHostsFile = "~/.ssh/known_hosts";
          controlMaster = "no";
          controlPath = "~/.ssh/master-%r@%n:%p";
          controlPersist = "no";
        };
      };
    };
  };

  darwinHomeModule.programs.ssh.matchBlocks."github.com".identityFile = "~/.ssh/id_rsa";
  nixosHomeModule.programs.ssh.matchBlocks."github.com".identityFile = "~/.ssh/id_ed25519";
}

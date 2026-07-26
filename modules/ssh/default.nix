{
  sharedHomeModule = {
    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;

      settings = {
        "github.com" = {
          HostName = "github.com";
          User = "git";
        };

        "*" = {
          ForwardAgent = false;
          AddKeysToAgent = "no";
          Compression = false;
          ServerAliveInterval = 120;
          ServerAliveCountMax = 3;
          HashKnownHosts = false;
          UserKnownHostsFile = "~/.ssh/known_hosts";
          ControlMaster = "no";
          ControlPath = "~/.ssh/master-%r@%n:%p";
          ControlPersist = "no";
        };
      };
    };
  };

  darwinHomeModule.programs.ssh.settings."github.com".IdentityFile = "~/.ssh/id_rsa";
  nixosHomeModule.programs.ssh.settings."github.com".IdentityFile = "~/.ssh/id_ed25519";
}

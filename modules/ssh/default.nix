{
  nixosSystemModule.services.openssh.enable = true;

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

  darwinHomeModule.programs.ssh.settings = {
    "github.com".IdentityFile = "~/.ssh/id_rsa";

    "tower" = {
      HostName = "192.168.168.10";
      User = "root";
      IdentityFile = "~/.ssh/id_rsa";
      IdentitiesOnly = true;
      ControlMaster = "auto";
      ControlPersist = "10m";
    };

    "router" = {
      HostName = "192.168.168.1";
      Port = 22222;
      User = "root";
      IdentityFile = "~/.ssh/id_rsa";
      IdentitiesOnly = true;
      ControlMaster = "auto";
      ControlPersist = "10m";
    };
  };
  nixosHomeModule.programs.ssh.settings."github.com".IdentityFile = "~/.ssh/id_ed25519";
}

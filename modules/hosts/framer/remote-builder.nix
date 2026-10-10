{
  nix.distributedBuilds = true;

  nix.buildMachines = [
    {
      hostName = "spike.local";
      sshUser = "nix-builder";
      sshKey = "/root/.ssh/id_ed25519";
      protocol = "ssh-ng";
      system = "x86_64-linux";
      maxJobs = 4;
      supportedFeatures = [
        "nixos-test"
        "benchmark"
        "big-parallel"
        "kvm"
      ];
    }
  ];

  nix.settings = {
    max-jobs = 0;
    builders-use-substitutes = true;
  };

  programs.ssh.knownHosts.spike = {
    hostNames = [ "spike.local" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICx43TohNiz/wJmnsiv1PzwVeVRRp3PhBTMFs5Ho9cp9";
  };
}

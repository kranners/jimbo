{
  programs.git = {
    enable = true;

    userName = "Aaron Pierce";
    userEmail = "aaron@cute.engineer";

    extraConfig = {
      push = { autoSetupRemote = true; };
      user = { signingkey = "53EAEA9DA697D60B"; };
      commit = { gpgsign = true; };
    };
  };
}

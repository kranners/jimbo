{
  programs.git = {
    enable = true;

    userName = "Aaron Pierce";
    userEmail = "aaron@cute.engineer";

    extraConfig = {
      push = {autoSetupRemote = true;};
      user = {signingkey = "6650E24854DEFD53";};
      commit = {gpgsign = true;};
    };
  };
}

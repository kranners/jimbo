{ pkgs, ... }: let
  git-cram = pkgs.writeShellApplication {
    name = "git-cram";

    runtimeInputs = [ pkgs.git ];

    text = ''
      git commit --amend --no-edit --no-verify
    '';
  };

  git-update = pkgs.writeShellApplication {
    name = "git-update";

    runtimeInputs = [ pkgs.git ];

    text = ''
      CURRENT_BRANCH="$(git symbolic-ref --short -q HEAD)"

      # TODO: Update this to take in an argument
      UPDATE_BRANCH="master"

      git switch "$UPDATE_BRANCH"
      git pull
      git switch "$CURRENT_BRANCH"
      git rebase "$UPDATE_BRANCH"
    '';
  };
in {
  home.packages = [ git-cram git-update ];

  # Set TTY for GPG to do hardware signing on commits
  programs.zsh.initExtraBeforeCompInit = ''
    export GPG_TTY=$(tty)
  '';
}

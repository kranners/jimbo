{ pkgs, ... }:
let
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

  git-update-merge = pkgs.writeShellApplication {
    name = "git-update-merge";

    runtimeInputs = [ pkgs.git ];

    text = ''
      CURRENT_BRANCH="$(git symbolic-ref --short -q HEAD)"

      # TODO: Update this to take in an argument
      UPDATE_BRANCH="master"

      git switch "$UPDATE_BRANCH"
      git pull
      git switch "$CURRENT_BRANCH"
      git merge "$UPDATE_BRANCH" --no-edit
    '';
  };
in
{
  home = {
    packages = [
      git-update
      git-update-merge
    ];

    shellAliases = {
      g = "git";
    };
  };

  programs.git = {
    enable = true;

    aliases = {
      cram = "commit --amend --no-edit --no-verify";
      s = "status";
    };
  };

  # Set TTY for GPG to do hardware signing on commits
  programs.zsh.initExtraBeforeCompInit = ''
    export GPG_TTY=$(tty)
  '';
}

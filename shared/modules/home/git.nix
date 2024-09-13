{ pkgs, ... }:
let
  runtimeInputs = [ pkgs.git ];

  git-update = pkgs.writeShellApplication {
    name = "git-update";
    inherit runtimeInputs;

    text = ''
      CURRENT_BRANCH="$(git symbolic-ref --short -q HEAD)"

      UPDATE_STRATEGY="$1"
      UPDATE_BRANCH="''${2:-master}"

      case "$UPDATE_STRATEGY" in
        merge|rebase)
          ;;
        *)
          echo "Usage: git update <merge|rebase> [update from branch, usually master]"
          exit 1 ;;
      esac

      git switch "$UPDATE_BRANCH"
      git pull
      git switch "$CURRENT_BRANCH"

      case "$UPDATE_STRATEGY" in
        "rebase") git rebase "$UPDATE_BRANCH" ;;
        "merge") git merge "$UPDATE_BRANCH" --no-edit ;;
      esac
    '';
  };

  git-shove = pkgs.writeShellApplication {
    name = "git-shove";
    inherit runtimeInputs;

    text = ''
      git add .
      git commit --amend --no-edit --no-verify
      git push --force
    '';
  };
in
{
  home = {
    packages = [
      git-update
      git-shove
    ];

    shellAliases = {
      g = "git";
    };
  };

  programs.git = {
    enable = true;

    difftastic.enable = true;

    aliases = {
      cram = "commit --amend --no-edit --no-verify";
      s = "status";
    };

    extraConfig.init.defaultBranch = "main";
  };

  # Set TTY for GPG to do hardware signing on commits
  programs.zsh.initExtraBeforeCompInit = ''
    export GPG_TTY=$(tty)
  '';
}

{ pkgs, ... }:
let
  runtimeInputs = [ pkgs.git ];

  git-update = pkgs.writeShellApplication {
    name = "git-update";
    inherit runtimeInputs;

    text = ''
      UPDATE_BRANCH="$(basename "$(git symbolic-ref refs/remotes/origin/HEAD)")"
      CURRENT_BRANCH="$(git symbolic-ref --short --quiet HEAD)"

      UPDATE_STRATEGY="''${1:-rebase}"

      git switch "$UPDATE_BRANCH"
      git pull
      git switch "$CURRENT_BRANCH"

      case "$UPDATE_STRATEGY" in
        "rebase") git rebase "$UPDATE_BRANCH" "''${@:2}" ;;
        "merge") git merge "$UPDATE_BRANCH" "''${@:2}" ;;
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

  git-skip = pkgs.writeShellApplication {
    name = "git-skip";
    inherit runtimeInputs;

    text = ''
      FILE_TO_SKIP="$1"
      CHECKOUT_STRATEGY="''${2:-theirs}"

      git checkout --"$CHECKOUT_STRATEGY" "$FILE_TO_SKIP"
      git add "$FILE_TO_SKIP"
      git rebase --continue
    '';
  };

  git-freshen = pkgs.writeShellApplication {
    name = "git-freshen";
    inherit runtimeInputs;

    text = ''
      UPDATE_BRANCH="$(basename "$(git symbolic-ref refs/remotes/origin/HEAD)")"

      git switch "$UPDATE_BRANCH"
      git pull --rebase
    '';
  };
in
{
  home = {
    packages = [
      git-update
      git-shove
      git-skip
      git-freshen
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

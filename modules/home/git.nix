{ pkgs, lib, ... }:
let
  runtimeInputs = [ pkgs.git ];

  git-update = pkgs.writeShellApplication {
    name = "git-update";
    inherit runtimeInputs;

    text = ''
      DEFAULT_UPDATE_BRANCH="$(basename "$(git symbolic-ref refs/remotes/origin/HEAD)")"
      CURRENT_BRANCH="$(git symbolic-ref --short --quiet HEAD)"

      UPDATE_STRATEGY="''${1:-rebase}"
      UPDATE_BRANCH="''${2:-$DEFAULT_UPDATE_BRANCH}"

      git switch "$UPDATE_BRANCH"
      git pull
      git switch "$CURRENT_BRANCH"

      case "$UPDATE_STRATEGY" in
        "rebase") git rebase "$UPDATE_BRANCH" "''${@:3}" ;;
        "merge") git merge "$UPDATE_BRANCH" "''${@:3}" ;;
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

  git-catchup = pkgs.writeShellApplication {
    name = "git-catchup";
    inherit runtimeInputs;

    text = ''
      git update rebase
      git push --force
    '';
  };

  git-new = pkgs.writeShellApplication {
    name = "git-new";
    inherit runtimeInputs;

    text = ''
      NEW_BRANCH_NAME="$1"

      git freshen
      git switch --create "$NEW_BRANCH_NAME"
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
      git-catchup
      git-new
    ];

    shellAliases = {
      g = "git";
    };
  };

  programs.git = {
    enable = true;

    aliases = {
      cram = "commit --amend --no-edit --no-verify";
    };

    extraConfig = {
      # show branches etc in table rather than list
      column.ui = "auto";

      # order branches by recent commits
      # order tags by semver
      branch.sort = "-committerdate";
      tag.sort = "version:refname";

      # dont make me pick a default branch
      init.defaultBranch = "main";

      # make diff smarter, especially with moves
      diff.algorithm = "histogram";

      # distinguish moves from add/remove in diffs
      diff.colorMoved = "plain";

      # replace a/b with i/w/c (index, worktree, commit)
      diff.mnemonicPrefix = true;

      # detect renamed files
      diff.renames = true;

      # create remote on push if not exist, and set tracking
      push.autoSetupRemote = true;

      # push local tags
      push.followTags = true;

      # delete local branches when deleted upstream
      fetch.prune = true;
      fetch.pruneTags = true;
      fetch.all = true;

      # show diffs in commit editor
      commit.verbose = true;

      # record rebase resolutions.
      rerere.enabled = true;
      rerere.autoaupdate = true;

      # auto everything for rebase
      rebase.autoSquash = true;
      rebase.autoStash = true;
      rebase.updateRefs = true;

      # automatically rebase on pull
      pull.rebase = true;
    };
  };

  # Set TTY for GPG to do hardware signing on commits
  programs.zsh.initContent = lib.mkOrder 550 ''
    export GPG_TTY=$(tty)
  '';
}

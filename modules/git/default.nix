{
  sharedHomeModule = { pkgs, lib, ... }:
    let
      runtimeInputs = [ pkgs.git ];

      git-update = pkgs.writeShellApplication {
        name = "git-update";
        inherit runtimeInputs;

        text = ''
          DEFAULT_UPDATE_BRANCH="$(basename "$(git symbolic-ref refs/remotes/origin/HEAD)")"

          UPDATE_STRATEGY="''${1:-rebase}"
          UPDATE_BRANCH="''${2:-$DEFAULT_UPDATE_BRANCH}"

          git fetch origin "$UPDATE_BRANCH"

          case "$UPDATE_STRATEGY" in
            "rebase") git rebase FETCH_HEAD "''${@:3}" ;;
            "merge") git merge FETCH_HEAD "''${@:3}" ;;
          esac
        '';
      };

      git-cram = pkgs.writeShellApplication {
        name = "git-cram";
        inherit runtimeInputs;

        text = ''
          git add .
          git commit --amend --no-edit --no-verify
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
          DEFAULT_UPDATE_BRANCH="$(basename "$(git symbolic-ref refs/remotes/origin/HEAD)")"
          UPDATE_BRANCH="''${1:-''$DEFAULT_UPDATE_BRANCH}"

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

      switch-environment = pkgs.writeShellApplication {
        name = "switch-environment";
        runtimeInputs = runtimeInputs ++ [ pkgs.coreutils ];

        text = ''
          MAIN="$(git worktree list --porcelain | head -1 | sed 's/^worktree //')"
          cp -R "$HOME/workspace/.environments/$(basename "$MAIN")/$1/." "$(git rev-parse --show-toplevel)/"
          echo "Switched $MAIN->$1"
        '';
      };

      git-tree = pkgs.writeShellApplication {
        name = "git-tree";
        inherit runtimeInputs;

        text = ''
          BRANCH="$1"
          BASE="''${2:-develop}"

          MAIN="$(git worktree list --porcelain | head -1 | sed 's/^worktree //')"
          TREE="$MAIN--$BRANCH"

          if [ ! -d "$TREE" ]; then
            if git show-ref --quiet "$BRANCH"; then
              git worktree add "$TREE" "$BRANCH" 1>&2
            else
              git worktree add -b "$BRANCH" "$TREE" "$BASE" 1>&2
            fi
          fi

          echo "$TREE"
        '';
      };

      git-untree = pkgs.writeShellApplication {
        name = "git-untree";
        inherit runtimeInputs;

        text = ''
          BRANCH="$1"

          MAIN="$(git worktree list --porcelain | head -1 | sed 's/^worktree //')"
          git worktree remove "$MAIN--$BRANCH" "''${@:2}"
        '';
      };

      git-tidy = pkgs.writeShellApplication {
        name = "git-tidy";
        runtimeInputs = runtimeInputs ++ [ pkgs.coreutils git-untree ];

        text = ''
          BASE="''${1:-$(basename "$(git symbolic-ref refs/remotes/origin/HEAD)")}"

          git fetch --prune
          git worktree prune

          CURRENT="$(git branch --show-current)"

          declare -A CANDIDATES=()

          while read -r BRANCH; do
            CANDIDATES["$BRANCH"]="merged into $BASE"
          done < <(git for-each-ref --merged "$BASE" --format='%(refname:short)' refs/heads)

          while read -r BRANCH TRACK; do
            if [ "$TRACK" = "[gone]" ]; then
              CANDIDATES["$BRANCH"]="upstream gone"
            fi
          done < <(git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads)

          unset "CANDIDATES[$BASE]"

          if [ -n "$CURRENT" ]; then
            unset "CANDIDATES[$CURRENT]"
          fi

          if [ "''${#CANDIDATES[@]}" -eq 0 ]; then
            echo "nothing to tidy"
            exit 0
          fi

          for BRANCH in "''${!CANDIDATES[@]}"; do
            if [ -n "$(git for-each-ref --format='%(worktreepath)' "refs/heads/$BRANCH")" ]; then
              if ! git untree "$BRANCH"; then
                echo "skipped $BRANCH: worktree not removable" >&2
                continue
              fi
            fi

            git branch --delete --force "$BRANCH"
            echo "removed $BRANCH (''${CANDIDATES[$BRANCH]})"
          done
        '';
      };

      git-rewrite = pkgs.writeShellApplication {
        name = "git-rewrite";
        inherit runtimeInputs;

        text = ''
          BASE="''${1:-develop}"

          git rebase --interactive "$(git merge-base HEAD "$BASE")"
        '';
      };

      git-new = pkgs.writeShellApplication {
        name = "git-new";
        inherit runtimeInputs;

        text = ''
          NEW_BRANCH_NAME="$1"
          UPDATE_BRANCH_NAME="$2"

          git freshen "$UPDATE_BRANCH_NAME"
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
        git-cram
        git-tree
        git-untree
        switch-environment
        git-rewrite
        git-tidy
      ];
    };

    programs.git = {
      enable = true;

      settings = {
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

        # record rebase resolutions
        rerere.enabled = true;
        rerere.autoaupdate = true;

        # auto everything for rebase
        rebase.autoSquash = true;
        rebase.autoStash = true;
        rebase.updateRefs = true;

        # automatically rebase on pull
        pull.rebase = true;

        # create local tracking branch when worktree-adding a remote-only branch
        worktree.guessRemote = true;

        user = {
          name = "Aaron";
          email = "aaron@cute.engineer";
        };
      };

      includes = [
        {
          condition = "gitdir:~/workspace/praxhub*/";
          path = "~/.config/git/work-config";
        }
      ];
    };

    xdg.configFile.gitWorkProfile = {
      target = "./git/work-config";

      text = ''
        [user]
          name = Aaron Pierce
          email = aaron@praxhub.com
      '';
    };

    programs.zsh.initContent = lib.mkOrder 550 ''
      tree() {
        cd "$(git tree "$@")" || return
        cmux workspace-action --action rename --title "$1"
      }
    '';
  };
}

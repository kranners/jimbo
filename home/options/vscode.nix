{ config, pkgs, lib, inputs, ... }:
let
  inherit (pkgs.vscode-utils) extensionFromVscodeMarketplace;

  aaron-pierce-nodash = extensionFromVscodeMarketplace {
    name = "nodash";
    publisher = "aaron-pierce";
    version = "1.2.0";
    sha256 = "+STw416hjpxz/gL0JTpmItueqUmMWkYZM7I1XCisLPc=";
  };
in {
  programs.vscode = {
    enable = true;

    # VSCode will update alongside everything else in the flake
    enableUpdateCheck = false;
    enableExtensionUpdateCheck = false;

    extensions =
      with inputs.nix-vscode-extensions.extensions.${pkgs.system}.vscode-marketplace; [
        astro-build.astro-vscode
        asvetliakov.vscode-neovim
        bbenoist.nix
        bradlc.vscode-tailwindcss
        brennondenny.vsc-jetbrains-icons-enhanced
        catppuccin.catppuccin-vsc
        catppuccin.catppuccin-vsc-icons
        chadalen.vscode-jetbrains-icon-theme
        codezombiech.gitignore
        dbaeumer.vscode-eslint
        esbenp.prettier-vscode
        firsttris.vscode-jest-runner
        isudox.vscode-jetbrains-keybindings
        jnoortheen.nix-ide
        brettm12345.nixfmt-vscode
        mgmcdermott.vscode-language-babel
        ms-python.debugpy
        ms-python.python
        ms-python.vscode-pylance
        ms-vscode.vscode-typescript-next
        ms-vsliveshare.vsliveshare
        streetsidesoftware.code-spell-checker
        usernamehw.errorlens
        wayou.vscode-todo-highlight
        yoavbls.pretty-ts-errors
      ];

    languageSnippets = {
      nix = {
        new-file = {
          prefix = "new";
          body = [
            "{"
            "  config,"
            "  pkgs,"
            "  lib,"
            "  inputs,"
            "  ..."
            "}: {"
            "  $0"
            "}"
          ];
        };
        multiline-string = {
          prefix = "ms";
          body = [ "''" "  $0" "'';" ];
        };
      };
    };

    userSettings = {
      # Prevent VSCode from opening parent folders, used because we deal in monorepos.
      "git.openRepositoryInParentFolders" = "always";

      # Auto save
      "files.autoSave" = "afterDelay";

      # Automatically update import locations when moving TS/JS files
      "typescript.updateImportsOnFileMove.enabled" = "always";
      "javascript.updateImportsOnFileMove.enabled" = "always";

      # Language specific features
      "[javascript,javascriptreact,typescript,typescriptreact]" = {
        "editor.defaultFormatter" = "esbenp.prettier-vscode";
      };

      "[css]" = { "editor.defaultFormatter" = "vscode.css-language-features"; };

      "[nix]" = {
        "editor.defaultFormatter" = "brettm12345.nixfmt-vscode";
        "editor.formatOnPaste" = true;
        "editor.formatOnSave" = true;
        "editor.formatOnType" = false;
      };

      # Settings for nixd and NixIDE
      "nix.enableLanguageServer" = true;
      "nix.serverPath" = "nixd";
      "nix.serverSettings" = {
        "nixd" = {
          "eval" = { };
          "formatting" = { "command" = "nixpkgs-fmt"; };
          "options" = {
            "enable" = true;
            "target" = {
              # tweak arguments here
              "args" = [ ];
              # NixOS options
              "installable" = "<flakeref>#nixosConfigurations.<name>.options";

              # Home-manager options
              # "installable" = "<flakeref>#homeConfigurations.<name>.options";
            };
          };
        };
      };

      # Auto formatting and linting on save.
      "editor.formatOnSave" = true;
      "eslint.format.enable" = true;
      "editor.codeActionsOnSave" = {
        "source.organizeImports" = "never";
        "source.addMissingImports" = "explicit";
        "source.fixAll.eslint" = "explicit";
        "eslint.applyAllFixes" = "explicit";
      };
      "eslint.workingDirectories" = [{ "mode" = "auto"; }];

      # Use Vim, can't ever hide line numbers
      "zenMode.hideLineNumbers" = false;

      # Set the icon theme
      "workbench.iconTheme" = "catppuccin-latte";

      # Show scrollbars (like JetBrains)
      "editor.scrollbar.verticalScrollbarSize" = 10;
      "editor.scrollbar.horizontalScrollbarSize" = 10;
      "editor.scrollbar.vertical" = "visible";
      "editor.scrollbar.horizontal" = "visible";

      # Use Sticky Scroll
      "editor.stickyScroll.enabled" = true;

      # Fonts (JetBrains font)
      "editor.fontFamily" =
        "'JetBrainsMono Nerd Font Mono', 'Font Awesome 6 Brands', 'Font Awesome 6 Free', 'Font Awesome 6 Free Solid', monospace";
      "editor.fontLigatures" = false;
      "editor.fontSize" = 14;
      "editor.fontWeight" = "350";
      "editor.letterSpacing" = -0.2;
      "editor.lineHeight" = 1.45;

      # Other editor configs
      "editor.tabSize" = 2;
      "editor.lineNumbers" = "relative";

      # Disable indentation lines (because they look bad)
      "editor.guides.indentation" = false;

      # Indent out the menu items (like JetBrains)
      "workbench.tree.indent" = 12;
      "workbench.colorTheme" = "Catppuccin Latte";
      "workbench.startupEditor" = "none";

      "vscode-neovim.neovimExecutablePaths.darwin" = "/opt/homebrew/bin/nvim";
      "vscode-neovim.neovimExecutablePaths.linux" =
        "/run/current-system/sw/bin/nvim";

      "extensions.experimental.affinity" = { "asvetliakov.vscode-neovim" = 1; };

      # Spell checker custom words
      "cSpell.userWords" = [
        "asvetliakov"
        "Catppuccin"
        "dbaeumer"
        "esbenp"
        "flakeref"
        "kamadorueda"
        "neovim"
        "nixd"
        "nixos"
        "nixpkgs"
        "nvim"
        "scrollback"
        "scrollbars"
      ];

      # Do not optimize for screen readers
      "editor.accessibilitySupport" = "off";

      # Prefer non-relative imports
      "javascript.preferences.importModuleSpecifier" = "non-relative";
      "typescript.preferences.importModuleSpecifier" = "non-relative";

      # I live on the edge, man
      "security.workspace.trust.enabled" = false;
      "security.workspace.trust.untrustedFiles" = "open";
      "explorer.confirmDragAndDrop" = false;
      "explorer.confirmDelete" = false;

      # Give me more lines in my terminal
      "terminal.integrated.scrollback" = 10000;
      "editor.minimap.enabled" = false;
      "[json]" = { "editor.defaultFormatter" = "esbenp.prettier-vscode"; };
    };
  };
}

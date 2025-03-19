# jimbo ❄️🧑‍🌾

[![Check flake](https://github.com/kranners/jimbo/actions/workflows/test.yml/badge.svg)](https://github.com/kranners/jimbo/actions/workflows/test.yml)

Flake for a home NixOS PC and a Macbook running nix-darwin.

Project structure:
```
📁  assets/      <-- static assets
📁  modules/     <-- config modules
    📁  neovim/  <-- neovim lua config
📁  darwin/      <-- legacy nix-darwin modules
📁  nixos/       <-- legacy nixos-modules
```

Trying to emulate [`nix-config-modules`](https://github.com/chadac/nix-config-modules) using `lib` functions.


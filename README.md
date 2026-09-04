# jimbo ❄️🧑‍🌾

[![Check flake](https://github.com/kranners/jimbo/actions/workflows/test.yml/badge.svg)](https://github.com/kranners/jimbo/actions/workflows/test.yml)

Flake for a home NixOS PC and a Macbook running nix-darwin.

Project structure:
```
📁  assets/      <-- static assets
📁  modules/     <-- config modules
    📁  hosts/   <-- per-machine facts
    📁  neovim/  <-- neovim lua config
```

Trying to emulate [`nix-config-modules`](https://github.com/chadac/nix-config-modules) using `lib` functions.


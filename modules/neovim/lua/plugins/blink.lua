return {
  "Saghen/blink.cmp",
  version = "1.*",
  build = "nix run .#build-plugin",
  opts = {
    keymap = {
      preset = "super-tab",
    },
    fuzzy = { implementation = "prefer_rust" },
  },
}

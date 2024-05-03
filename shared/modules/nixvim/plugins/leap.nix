{
  programs.nixvim = {
    plugins.leap.enable = true;

    keymaps = [
      {
        key = "s";
        action = "<CMD>lua require('leap').leap { target_windows = require('leap.user').get_focusable_windows() }<CR>";
        options = { desc = "Leap across windows"; };
        mode = "n";
      }
    ];
  };
}

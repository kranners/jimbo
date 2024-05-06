let
  RESIZE_SIZE = "5";

  mkMovement = key: direction: {
    key = "<C-${key}>";
    action = "<CMD>wincmd ${key}<CR>";
    options = { desc = "Focus window ${direction}"; };
    mode = [ "t" "n" "i" ];
  };

  mkRearrange = wincmd: key: {
    key = "<Leader><${key}>";
    action = "<CMD>wincmd ${wincmd}<CR>";
    options = { desc = "Send window to ${key}"; };
    mode = "n";
  };

  mkResize = key: grow: vertical:
    let
      sign =
        if grow
        then "+"
        else "-";
      prefix =
        if vertical
        then "vertical "
        else "";
    in
    {
      key = "<${key}>";
      action = "<CMD>${prefix}resize ${sign}${RESIZE_SIZE}<CR>";
      mode = "n";
    };
in
{
  programs.nixvim.keymaps = [
    # Make new windows
    {
      key = "<Leader>n";
      action = "<CMD>split<CR>";
      options = { desc = "Make a new horizontal split"; };
      mode = "n";
    }
    {
      key = "<Leader>N";
      action = "<CMD>vsplit<CR>";
      options = { desc = "Make a new vertical split"; };
      mode = "n";
    }

    # Window movement motions
    (mkMovement "h" "left")
    (mkMovement "j" "down")
    (mkMovement "k" "up")
    (mkMovement "l" "right")

    # Window relative rearranging
    (mkRearrange "H" "Left")
    (mkRearrange "J" "Down")
    (mkRearrange "K" "Up")
    (mkRearrange "L" "Right")

    # Window resizing
    (mkResize "Left" true true)
    (mkResize "Down" true false)
    (mkResize "Up" false false)
    (mkResize "Right" false true)
  ];
}

{ config
, pkgs
, inputs
, ...
}: {
  fonts.packages = with pkgs; [ font-awesome nerdfonts fira-code-nerdfont ];
}

{
  darwinSystemModule = {
    security.pam.services.sudo_local.touchIdAuth = true;

    system = {
      keyboard = {
        enableKeyMapping = true;
        remapCapsLockToControl = true;
      };

      defaults = {
        finder = {
          AppleShowAllExtensions = true;
          FXPreferredViewStyle = "clmv";
        };

        screencapture.location = "~/Pictures";
      };
    };
  };
}

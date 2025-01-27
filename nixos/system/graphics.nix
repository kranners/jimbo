{ pkgs, ... }: {
  hardware.graphics = {
    enable = true;
    enable32Bit = true;

    extraPackages = [
      pkgs.amdvlk
      pkgs.libva-utils
    ];
  };

  environment.variables.AMD_VULKAN_ICD = "RADV";
}

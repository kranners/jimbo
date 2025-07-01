{
  nixosSystemModule.services.ollama = {
    enable = true;

    acceleration = "rocm";
    rocmOverrideGfx = "10.3.0";
    host = "0.0.0.0";
  };
}

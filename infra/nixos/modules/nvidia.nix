{ config, pkgs, ... }:

{
  hardware.nvidia = {
    modesetting.enable = true;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # Enable OpenGL
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
  };


  # Enable NVIDIA driver
  # services.xserver.videoDrivers = [ "nvidia" ];

  # Enable OpenGL
  # hardware.opengl.enable = true;
  # hardware.opengl.driSupport32Bit = true;

  # Enable the NVIDIA settings menu
  # hardware.nvidia.nvidiaSettings = true;

  # Set the NVIDIA card as primary
  # hardware.nvidia.prime = {
  #   sync.enable = true;
  #   nvidiaBusId = "PCI:1:0:0";
  #   intelBusId = "PCI:0:2:0";
  # };

}

{pkgs, ...}:
{
  # Enable KDE Plasma
  services.xserver = {
    enable = true;
    layout = "de";  # Set the keyboard layout to German
    # desktopManager.plasma5.enable = true;
  };

  services.desktopManager.plasma6.enable = true;

  # Enable Wayland for SDDM
  services.displayManager.sddm.wayland.enable = true;

  environment.systemPackages = with pkgs; [
    libsForQt5.plasma-wayland-protocols
    # required for kwallet to generate gpg key with passphrase
    pinentry
  ];

  # Optional: If you want to use the same layout in the console
  i18n.consoleUseXkbConfig = true;  # Use XKB settings for console
}

{pkgs, ...}:
{
  # Enable gnome keyring.
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.lightdm.enableGnomeKeyring = true;

  # Use Seahorse (GNOME Keyring GUI)
  environment.systemPackages = [
    pkgs.gnome.seahorse
    pkgs.libsecret
  ];
}

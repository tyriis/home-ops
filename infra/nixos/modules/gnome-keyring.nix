{pkgs, ...}:
{
  # Enable gnome keyring.
  services.gnome.gnome-keyring.enable = true;
  # security.pam.services.lightdm.enableGnomeKeyring = true;
  # switch to wayland and greetd
  security.pam.services.greetd.enableGnomeKeyring = true;

  # Use Seahorse (GNOME Keyring GUI)
  environment.systemPackages = [
    pkgs.gnome.seahorse
    pkgs.libsecret
  ];
}

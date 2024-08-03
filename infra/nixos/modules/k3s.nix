{
  # Enable k3s
  services.k3s = {
    enable = true;
    role = "server";
    extraFlags = toString [
      "--flannel-backend=none" # https://docs.k3s.io/installation/network-options
      "--disable=coredns" # https://docs.k3s.io/networking#coredns
      "--disable=traefik" # https://docs.k3s.io/networking#traefik-ingress-controller
      "--disable-network-policy" # https://docs.k3s.io/networking#network-policy-controller
      "--disable=servicelb" # https://docs.k3s.io/networking#disabling-servicelb
      "--disable=metrics-server" # https://docs.k3s.io/installation/packaged-components?_highlight=metric#using-the---disable-flag
      "--disable local-storage"
    ];
  };

  # prevent deploymnet of local-storage
  environment.etc."rancher/k3s/server/manifests/local-storage.yaml.skip".text = "";
}

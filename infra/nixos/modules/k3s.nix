{ inputs, config, lib, pkgs, ... }:
{
  # install k3s package
  environment.systemPackages = with pkgs; [ k3s ];

  # enable k3s systemd service
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
    ];
  };

  # prevent deploymnet of local-storage
  environment.etc."rancher/k3s/server/manifests/local-storage.yaml.skip".text = "";

  # copy /etc/rancher/k3s/k3s.yaml to /home/nils/.kube/config
  systemd.services = {
    k3s-post-restart-nils = {
      description = "K3s post-restart actions for nils";
      after = [ "k3s.service" ];
      wants = [ "k3s.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = ''
          ${pkgs.bash}/bin/bash -c '\
          ${pkgs.coreutils}/bin/mkdir -p /home/nils/.kube && \
          ${pkgs.coreutils}/bin/chown nils:users /home/nils/.kube'
          ${pkgs.coreutils}/bin/cp /etc/rancher/k3s/k3s.yaml /home/nils/.kube/config && \
          ${pkgs.coreutils}/bin/chown nils:users /home/nils/.kube/config'
        '';
      };
    };

  # copy /etc/rancher/k3s/k3s.yaml to /home/jasmin/.kube/config
    k3s-post-restart-jasmin = {
      description = "K3s post-restart actions for jasmin";
      after = [ "k3s.service" ];
      wants = [ "k3s.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = ''
          ${pkgs.bash}/bin/bash -c '\
          ${pkgs.coreutils}/bin/mkdir -p /home/jasmin/.kube && \
          ${pkgs.coreutils}/bin/chown jasmin:users /home/jasmin/.kube'
          ${pkgs.coreutils}/bin/cp /etc/rancher/k3s/k3s.yaml /home/jasmin/.kube/config && \
          ${pkgs.coreutils}/bin/chown -r jasmin:users /home/jasmin/.kube/config'
        '';
      };
    };
  };

}

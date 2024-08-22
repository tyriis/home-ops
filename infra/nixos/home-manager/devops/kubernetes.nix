{ pkgs, ... }:
{
  home.packages = with pkgs; [
    fluxcd
    kubectl
    kubectl-view-allocations
    kubectl-view-secret
    pkgs.unstable.kubecolor
    kubernetes-helm
    kustomize
    k9s
  ];
}

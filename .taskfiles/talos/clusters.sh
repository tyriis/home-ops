# shellcheck shell=bash
# Shared per-cluster constants — the ONLY place endpoints/nodes are defined.
# Sourced by render-config.sh and gen-talosconfig.sh.
# usage: cluster_config <cluster>   → sets CLUSTER_NAME, ENDPOINT
cluster_config() {
  case "$1" in
    main)    CLUSTER_NAME="main";    ENDPOINT="https://192.168.100.100:6443" ;;
    utility) CLUSTER_NAME="utility"; ENDPOINT="https://192.168.100.30:6443" ;;
    *) echo "unknown cluster: $1 (known: main, utility)" >&2; return 1 ;;
  esac
}

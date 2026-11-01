#!/usr/bin/env bash
# Rolling etcd defrag for a cluster.
#
#   usage: etcd-defrag.sh <cluster> <threshold-pct> <ip> [ip...]
#
# Nodes are processed STRICTLY in the order given, one at a time (etcd's own
# guidance: defrag is resource-heavy, never on several members at once).
# Convention: non-control-plane IPs first, control-plane IPs last, e.g.
#   etcd-defrag.sh main 50 192.168.100.120 192.168.100.101 192.168.100.102 192.168.100.103
#
# Per node:
#   - non etcd-member (worker) -> nothing to defrag, reported + skipped
#   - control plane: defrag ONLY if its DB free space exceeds THRESHOLD%
#     (free = 100% - the "IN USE %" from etcd status)
#   - control-plane members are reordered so the etcd LEADER goes LAST —
#     followers defrag first, minimum quorum disruption
# After each defrag: that member's status re-checked. At the end: the full
# cluster status table is printed as the report.
#
# Exit: 0 success (defragged or correctly skipped), non-zero if a member errored.
set -euo pipefail

cluster="${1:?usage: etcd-defrag.sh <cluster> <threshold-pct> <ip> [ip...]}"
threshold="${2:?usage: etcd-defrag.sh <cluster> <threshold-pct> <ip> [ip...]}"
shift 2
[[ $# -ge 1 ]] || { echo "no node IPs given" >&2; exit 2; }

ts() { command -v "$1" >/dev/null || { echo "missing binary: $1" >&2; exit 3; }; }
ts talosctl; ts awk

tal() { talosctl --context "$cluster" "$@"; }

# etcd status table for one node -> single data row
# Columns are multi-token ("285 MB", "152 MB (53.22%)"): $1=node $2=memberid
# $3-4=db size $5-7=in use + percent $8=leaderid
member_status() { tal -n "$1" etcd status 2>/dev/null | tail -1; }
in_use_pct() { awk '{print $7}' <<<"$1" | tr -d '()%'; }
member_id()  { awk '{print $2}' <<<"$1"; }
leader_id()  { awk '{print $8}' <<<"$1"; }

echo "cluster=$cluster threshold=${threshold}% free-space, nodes in requested order: $*"

# --- classify: etcd members vs non-members, and find the leader id ---
declare -A IN_USE FREE LEADER_ID MEMBER_NAME
members=()
for ip in "$@"; do
  row="$(member_status "$ip" || true)"
  if [[ -z "$row" || "$row" != "$ip"* ]]; then
    echo "==> $ip: no etcd member here (worker) — nothing to defrag, skipping"
    continue
  fi
  name=$(member_id "$row")
  in_use_pct=$(in_use_pct "$row")
  [[ -n "$in_use_pct" ]] || { echo "!! $ip: could not parse status: $row" >&2; exit 4; }
  IN_USE[$ip]=$in_use_pct; FREE[$ip]=$(awk -v v="$in_use_pct" 'BEGIN{printf "%.2f", 100-v}')
  MEMBER_NAME[$ip]=$name
  members+=("$ip")
  echo "member $ip (${MEMBER_NAME[$ip]}): ${IN_USE[$ip]}% in use, ${FREE[$ip]}% free"
done
[[ ${#members[@]} -gt 0 ]] || { echo "no etcd members found among the given nodes"; exit 0; }

# leader id: compare each member's own id vs the leader field from its status
for ip in "${members[@]}"; do
  row="$(member_status "$ip")"
  [[ "$(member_id "$row")" != "$(leader_id "$row")" ]] || LEADER_ID=$(member_id "$row")
done
for ip in "${members[@]}"; do
  [[ "${MEMBER_NAME[$ip]}" != "${LEADER_ID:-}" ]] || { leader_ip=$ip; }
done

# --- order: non-leader members first, leader LAST ---
queue=()
for ip in "${members[@]}"; do
  [[ "$ip" != "${leader_ip:-}" ]] && queue+=("$ip")
done
[[ -n "${leader_ip:-}" ]] && queue+=("$leader_ip")

echo "etcd leader: ${leader_ip:-unknown} — order: $(IFS=' '; echo "${queue[*]}")"

# --- one at a time, never in parallel ---
defragged=()
for ip in "${queue[@]}"; do
  if awk -v f="${FREE[$ip]}" -v t="$threshold" 'BEGIN{exit !(f > t)}'; then
    echo "==> $ip: ${FREE[$ip]}% free > ${threshold}% — defragmenting (blocking)..."
    tal -n "$ip" etcd defrag
    echo "    after: $(member_status "$ip" | awk '{print $5, $6, $7}')"
    defragged+=("$ip")
  else
    echo "==> $ip: ${FREE[$ip]}% free <= ${threshold}% — skipping"
  fi
done

echo
echo "===== FINAL etcd cluster status ====="
for ip in "${members[@]}"; do
  tal -n "$ip" etcd status
done | awk 'NR==1 || /192\./{print}'
echo
if [[ ${#defragged[@]} -eq 0 ]]; then
  echo "no member exceeded ${threshold}% free space — nothing defragmented."
else
  echo "defragmented: ${defragged[*]}"
fi

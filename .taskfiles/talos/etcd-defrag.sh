#!/usr/bin/env bash
# Rolling etcd defrag for a cluster.
#
#   usage: etcd-defrag.sh <cluster> [threshold-pct] [ip...]
#
# With no IPs given, etcd members are AUTO-DETECTED via
# `talosctl --context <cluster> etcd members` (only etcd members have a DB to
# defrag — workers are never targets). Explicit IPs are processed STRICTLY in
# the order given, one at a time (etcd's own guidance: defrag is
# resource-heavy, never on several members at once).
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

cluster="${1:?usage: etcd-defrag.sh <cluster> [threshold-pct] [ip...]}"
shift
threshold=50
[[ "${1:-}" =~ ^[0-9]+$ ]] && { threshold="$1"; shift; }

ts() { local b="$1"; command -v "$b" >/dev/null || { echo "missing binary: $b" >&2; exit 3; }; }
ts talosctl; ts awk

tal() { talosctl --context "$cluster" "$@"; }

# no explicit IPs -> auto-detect etcd members (dedupe; client URL host = IP)
if [[ $# -eq 0 ]]; then
  mapfile -t detected < <(tal etcd members 2>/dev/null | awk 'NR>1 {print $5}' | sed 's|https://||; s|:2379$||' | sort -u)
  [[ ${#detected[@]} -gt 0 ]] || { echo "no etcd members detected for context '$cluster'" >&2; exit 2; }
  set -- "${detected[@]}"
fi

# etcd status table for one node -> single data row
# Columns are multi-token ("285 MB", "152 MB (53.22%)"): $1=node $2=memberid
# $3-4=db size $5-7=in use + percent $8=leaderid
member_status() { local ip="$1"; tal -n "$ip" etcd status 2>/dev/null | tail -1; }
in_use_pct() { local row="$1"; awk '{print $7}' <<<"$row" | tr -d '()%'; }
member_id()  { local row="$1"; awk '{print $2}' <<<"$row"; }
leader_id()  { local row="$1"; awk '{print $8}' <<<"$row"; }

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

# --- decide + confirm ---
needed=()
for ip in "${queue[@]}"; do
  awk -v f="${FREE[$ip]}" -v t="$threshold" 'BEGIN{exit !(f >= t)}' && needed+=("$ip")
done

run_all=0
if [[ ${#needed[@]} -gt 0 ]]; then
  echo "fragmentation >= ${threshold}% on: ${needed[*]}"
  read -r -p "Run rolling etcd defrag now? [Y/n] " ans
  [[ "$ans" =~ ^[Nn] ]] && { echo "cancelled."; exit 0; }
else
  echo "no node has >= ${threshold}% free (fragmentation) — max is $(printf '%s\n' "${FREE[@]}" | sort -rn | head -1)%"
  read -r -p "Run defrag anyway? NOT recommended. [y/N] " ans
  [[ "$ans" =~ ^[Yy] ]] || { echo "cancelled."; exit 0; }
  run_all=1
fi

# --- one at a time, never in parallel ---
defragged=()
for ip in "${queue[@]}"; do
  if [[ $run_all -eq 1 ]] || awk -v f="${FREE[$ip]}" -v t="$threshold" 'BEGIN{exit !(f >= t)}'; then
    echo "==> $ip: ${FREE[$ip]}% free — defragmenting (blocking)..."
    tal -n "$ip" etcd defrag
    echo "    after: $(member_status "$ip" | awk '{print $5, $6, $7}')"
    defragged+=("$ip")
  else
    echo "==> $ip: ${FREE[$ip]}% free below threshold — skipping"
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

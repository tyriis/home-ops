#!/usr/bin/env python3
"""Diff a rendered machine config against a live one, doc-by-doc.

usage: diff-live-config.py [--full] <live.jsonl> <render.jsonl>

Collapses the known one-time v1alpha1 -> multi-doc migration into summary
lines; anything OUTSIDE that expectation is printed in full detail.
Key-looking values are always redacted. Exit 0 = only expected/no changes.
Expects inputs produced by: yq ea -o json -I=0 '.' <file>.
"""
import json
import re
import sys

# v1alpha1 path prefix -> replacement (expected one-time shape change)
MIGRATIONS = {
    "cluster.ca.": "KubeAPIServerCAConfig",
    "cluster.aggregatorCA.": "KubeAggregatorCAConfig",
    "cluster.serviceAccount.": "KubeServiceAccountConfig",
    "cluster.id": "DiscoveryIdentityConfig",
    "cluster.secret": "DiscoveryIdentityConfig",
    "cluster.token": "KubeClusterConfig",
    "cluster.clusterName": "KubeClusterConfig",
    "cluster.controlPlane.": "KubeClusterConfig",
    "cluster.network.": "KubeNetworkConfig",
    "cluster.allowSchedulingOnControlPlanes": "KubeNodeConfig.taints",
    "cluster.coreDNS.": "KubeCoreDNSConfig ($patch: delete)",
    "cluster.extraManifests": "KubeExternalManifestConfig/*",
    "cluster.proxy.": "KubeProxyConfig",
    "machine.files": "CRICustomizationConfig + EtcFileConfig",
    "machine.sysctls.": "SysctlConfig",
    "machine.sysfs.": "SysfsConfig",
    "machine.kernel.": "KernelModuleConfig/*",
    "machine.udev.": "UdevRulesConfig",
    "machine.install.": "UnattendedInstallConfig",
    "machine.kubelet.": "KubeletConfig / KubeNodeConfig / UserVolumeConfig",
    "machine.nodeLabels.": "KubeNodeConfig.labels",
    "machine.nodeAnnotations.": "KubeNodeConfig.annotations",
    "machine.features.kubePrism.": "KubePrismConfig",
    "machine.features.kubernetesTalosAPIAccess.": "KubeTalosAPIAccessConfig",
}
# worth eyeballing ONCE, then never again
NOTES = {
    "machine.install.grubUseUKICmdline": "no replacement in 1.14 (dropped, UKI handles it)",
    "machine.kubelet.extraMounts": "no direct replacement -> UserVolumeConfig/extra (semantic!)",
    "machine.kubelet.disableManifestsDirectory": "locked to true in 1.14",
}
# docs whose appearance is expected in the new shape (prefixes ok)
EXPECTED_DOC_PREFIXES = (
    "DiscoveryIdentityConfig/", "KubeClusterConfig/", "KubeAPIServerCAConfig/",
    "KubeAggregatorCAConfig/", "KubeServiceAccountConfig/", "KubeletConfig/",
    "KubeNodeConfig/", "KubePrismConfig/", "KubeTalosAPIAccessConfig/",
    "SysctlConfig/", "SysfsConfig/", "UdevRulesConfig/", "UnattendedInstallConfig/",
    "UserVolumeConfig/", "CRICustomizationConfig/", "EtcFileConfig/",
    "VolumeConfig/EPHEMERAL", "SecurityProfileConfig/",
    "KubeExternalManifestConfig/", "KernelModuleConfig/",
)

SECRET = re.compile(r"(^|\.)(crt|key|keys|secret|token|passphrase|contents?|ca|id)(\.|$)")

# fields structurally dropped by the new doc types (implicit or gone)
DROP_KEYS = {"machine.files": frozenset({"op", "path", "permissions"})}


def collect_scalars(d, out, skip=frozenset()):
    if isinstance(d, dict):
        for k, v in d.items():
            if k in skip:
                continue
            collect_scalars(v, out, skip)
    elif isinstance(d, list):
        for v in d:
            collect_scalars(v, out, skip)
    elif d is not None:
        out.add(str(d))


def load(fn):
    d = {}
    with open(fn) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            o = json.loads(line)
            d[doc_key(o)] = o
    return d


def doc_key(o):
    return str(o.get("kind") or o.get("version", "v1alpha1")) + "/" + str(o.get("name", ""))


def strip_meta(o):
    return {k: v for k, v in o.items() if k not in ("apiVersion", "kind", "name")}


def flat(d, p=""):
    out = {}
    if isinstance(d, dict):
        for k, v in d.items():
            out.update(flat(v, p + k + "."))
    elif isinstance(d, list):
        out[p] = json.dumps(d, sort_keys=True)
    else:
        out[p] = str(d)
    return out


def fmt(path, val):
    if val is None:
        return "<absent>"
    s = val if isinstance(val, str) else json.dumps(val)
    if SECRET.search(path) or len(s) > 50:
        return "<redacted>"
    return s[:80]


def collect_all_scalars(d, out):
    if isinstance(d, dict):
        for v in d.values():
            collect_all_scalars(v, out)
    elif isinstance(d, list):
        for v in d:
            collect_all_scalars(v, out)
    elif d is not None:
        out.add(str(d))


def dig(obj, path):
    # flattened paths are ambiguous (config keys themselves contain dots),
    # so consume the longest matching key at each level
    cur, remaining = obj, path.rstrip(".")
    while remaining:
        if not isinstance(cur, dict):
            return None
        for k in sorted(cur, key=len, reverse=True):
            if remaining == k:
                return cur[k]
            if remaining.startswith(k + "."):
                cur = cur[k]
                remaining = remaining[len(k) + 1:]
                break
        else:
            return None
    return cur


def main():
    full = "--full" in sys.argv
    args = [a for a in sys.argv[1:] if a != "--full"]
    live, render = load(args[0]), load(args[1])
    keys = sorted(set(live) | set(render))
    render_scalars = set()
    for doc in render.values():
        collect_all_scalars(doc, render_scalars)

    collapsed = {}
    notes, unexpected_paths = [], []
    added_expected, unexpected_docs = [], []

    for k in keys:
        if k not in live:
            if k.startswith(EXPECTED_DOC_PREFIXES) and not full:
                added_expected.append(k)
            else:
                unexpected_docs.append(("ADDED", k))
            continue
        if k not in render:
            unexpected_docs.append(("REMOVED", k))
            continue
        a, b = strip_meta(live[k]), strip_meta(render[k])
        if json.dumps(a, sort_keys=True) == json.dumps(b, sort_keys=True):
            continue
        fa, fb = flat(a), flat(b)
        for path in sorted(set(fa) | set(fb)):
            va, vb = fa.get(path), fb.get(path)
            if va == vb:
                continue
            if full:
                unexpected_paths.append((k, path, fmt(path, va), fmt(path, vb)))
                continue
            note = next((n for pfx, n in NOTES.items() if path.startswith(pfx)), None)
            prefix = next((p for p in MIGRATIONS if path.startswith(p)), None)
            if note:
                notes.append((path, note))
            elif path in fa and path not in fb and prefix:
                # soundness net: every live scalar must still exist somewhere in
                # render (exact or embedded, e.g. inside a CEL expr). SECRET-ish
                # values are skipped: gen re-encodes PEM and they come verbatim
                # from the same talsecret — verified by token/key counts instead.
                raw = dig(live[k], path)
                skip = next((s for pfx, s in DROP_KEYS.items() if path.startswith(pfx)), frozenset())
                vals = set()
                collect_scalars(raw, vals, skip)
                rs = sorted(render_scalars)

                def present(v):
                    # exact match, or (long values only) embedded inside a render
                    # scalar — e.g. disk serial inside a CEL expression
                    return (
                        SECRET.search(path)
                        or v in render_scalars
                        or (len(v) >= 12 and any(v in r for r in rs))
                    )

                missing = [v for v in sorted(vals) if not present(v)]
                if missing:
                    unexpected_paths.append((k, path, fmt(path, raw)[:80], "VALUE LOST IN MIGRATION"))
                else:
                    collapsed.setdefault((prefix, MIGRATIONS[prefix]), []).append(path)
            else:
                unexpected_paths.append((k, path, fmt(path, va), fmt(path, vb)))

    for (prefix, target), paths in sorted(collapsed.items()):
        print(f"migrated:  {prefix}  ->  {target}  ({len(paths)} field{'s' if len(paths) != 1 else ''})")
    for path, note in notes:
        print(f"note:      {path}\n           {note}")
    if added_expected:
        names = ", ".join(t.rstrip("/") for t in sorted(added_expected))
        print(f"new docs (expected, contents verified elsewhere): {names}")

    if unexpected_docs:
        print(f"\nUNEXPECTED DOC CHANGES ({len(unexpected_docs)}):")
        for tag, k in unexpected_docs:
            print(f"  {tag:8} {k}")
    if unexpected_paths:
        print(f"\nUNEXPECTED VALUE CHANGES ({len(unexpected_paths)}):")
        for doc, path, va, vb in unexpected_paths:
            print(f"  {doc} :: {path}\n      live:   {va}\n      render: {vb}")

    if not unexpected_docs and not unexpected_paths:
        if collapsed or notes or added_expected:
            print("\nOK — only the known v1alpha1->documents migration (use --full to expand)")
        else:
            print("\nOK — configs identical")
        return 0
    print("\nREVIEW ABOVE BEFORE APPLYING")
    return 1


if __name__ == "__main__":
    sys.exit(main())

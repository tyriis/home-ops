---
status: accepted
date: 2026-10-26
decision-makers: [tyriis]
---

# Reject Graphify as a local code-graph layer for this repo

## Context and Problem Statement

Agents working in this repo answer cross-cutting questions by grep: which apps reference a shared
component, what a Kustomization pulls in, what breaks when `kubernetes/components/volsync`
changes. Graphify (`graphifyy` 0.9.95, CLI `graphify`) claims to turn any folder into a queryable
knowledge graph, "application code, database schema and infrastructure in one graph", and was
evaluated as a replacement for that grep loop.

The repo is 1,501 tracked files / 2.6 MB: 1,252 YAML, 119 Markdown, 6 shell, 3 Terraform, no
vendored charts and no file above 1 MB. A full AST build is cheap. The question was never cost; it
was whether the graph contains the edges the questions need.

## Decision Drivers

- The questions are about edges **between** manifests (Kustomization → HelmRelease/OCIRepository →
  namespace), not about symbols inside a single file.
- 75 manifests are `kind: ExternalSecret`; OpenBao → External Secrets Operator is a core
  convention, so a graph that omits them is wrong about the repo's plumbing.
- Tooling must be exactly pinned in `.mise.toml` and reproducible from a clean checkout.
- An agent instruction such as "query before you grep" is only safe if a graph miss means
  "absent", not "not indexed".

## Considered Options

1. **Graphify AST tier** over the tracked tree (`graphify extract . --code-only`).
2. **Graphify semantic tier** over `docs/decisions/` only, with LLM extraction.
3. **Status quo**: `rg`, `kustomize build` / `task flate:test`, `deadvalues`, Hindsight memory.

## Decision Outcome

Chosen option 3: **reject Graphify and keep the status quo.**

Measured on 2026-10-26 with graphify 0.9.95 at commit `97eba80`, 1,099 code files:

| Measurement                  | Result                                                              |
| ---------------------------- | ------------------------------------------------------------------- |
| Build cost                   | 8.6 s, 0 tokens, no network                                         |
| Graph size                   | 24,030 nodes, 24,667 edges, 1,921 communities                       |
| Edge types                   | `contains` 24,665 · `calls` 1 · `defines` 1                         |
| Node composition             | 21,488 bare YAML keys (89%) · 1,896 file nodes · 646 resource nodes |
| Top god nodes                | `default` ×4 (43 edges), `data` ×4 (29), `name` (26)                |
| `GRAPH_REPORT.md`            | 306 KB, unlabelled `Community 0` … `Community 1905`                 |
| `HelmRelease` nodes          | 11 (156 files contain `kind: HelmRelease`)                          |
| `Kustomization` nodes        | 115 (374 files)                                                     |
| `OCIRepository` nodes        | 0 (66 files)                                                        |
| `ExternalSecret` nodes       | 0 (75 files)                                                        |
| Files dropped by name filter | 65, including every `external-secret.yaml`                          |

The deciding finding is the edge mix: the extractor emits one edge per file, `contains`, from the
file to its own top-level keys. It does not resolve a reference to another file, so no
`resources:` → directory, no `sourceRef` → OCIRepository, no `secretKeyRef` → Secret edge exists.
`graphify explain "Kustomization ai"` returns no node, because a kustomize file carries no `kind`,
and a Flux `Kustomization` node has no edge to the `HelmRelease` it manages.

## Pros and Cons of the Options

### Graphify AST tier — rejected

- Good: fast and free (8.6 s, zero tokens), and secret hygiene held — the build contained zero
  matches for SOPS ciphertext, `AGE-SECRET-KEY`, `sops.env`, `docs/superpowers` or `docker/`.
- Bad: 24,665 of 24,667 edges are containment, so the graph cannot answer any wiring question.
- Bad: coverage is arbitrary rather than shallow — 7% of HelmReleases, none of the
  OCIRepositories, none of the ExternalSecrets.
- Bad: 65 manifests are silently dropped by a hardcoded filename heuristic (stem ending in
  `secret`) with no opt-out flag; the repo's External Secrets layer is invisible as a result.
- Bad: 3 `.tf` files contribute nothing without the `terraform` extra.
- Bad: 89% of nodes are bare keys, so `god-nodes` ranks `default` and `data` as the architecture
  and `query` spends its token budget on `spec`/`metadata`/`apiVersion` hits.

### Graphify semantic tier — not adopted

- Good: the only mode that produces real cross-document edges (`supersedes`, `depends_on` between
  ADRs), and it is what `--mode deep` is for.
- Bad: 22 ADRs / 148 KB are answered by `rg` in milliseconds, and Hindsight memory already indexes
  ADRs, commits and sessions semantically. The graph would add a browsable diagram, not better
  retrieval.
- Bad: install is not reproducible under this repo's conventions. `mise`'s `pipx:` backend cannot
  pass extras (`pipx:graphifyy[openai]` reinstalls the plain package) and its venv has no `pip`,
  so the `openai` SDK had to be injected with `uv pip install --python <venv>`, which
  `mise install --force` discards.
- Bad: the `techtales.ai/v1` gateway model (`qwen3.8-flash-next`) is a reasoning model; it spends
  output budget on reasoning tokens before emitting JSON, so chunk output must be raised well above
  the defaults. The 22-ADR run produced no graph and was abandoned.

### Status quo — chosen

- `rg` covers the whole tree with no coverage gap, including the 75 ExternalSecret manifests.
- `kustomize build` / `task flate:test` answers include/ref wiring and fails loudly when it is
  wrong; `deadvalues` already scans Helm values in CI.
- Hindsight memory answers "why" with ADR and commit context.

## Consequences

- No `graphify` pin, no `.graphifyignore`, no task namespace, no `AGENTS.md` rule, no git hooks
  and no CI job. The evaluation left nothing tracked: the pin commit was reverted, the plan and
  the gitignored artifacts were deleted, and the tool was uninstalled from `mise`.
- The graph would have been local-only by design, so no teammate loses a shared artifact.
- **Revisit only if** upstream emits cross-file YAML reference edges (`resources`,
  `chartRef`/`sourceRef`, `secretKeyRef`) **and** provides an opt-out for the secret-filename
  filter. Without both, "query before grep" stays unsafe: a miss in a graph covering 7% of
  HelmReleases reads exactly like "this does not exist".
- Local knowledge graphs remain the right shape for source-code repos. This repo is 96%
  YAML-plus-Markdown with one `calls` edge in it, which is not what Graphify indexes.

## More Information

- Graphify: <https://github.com/Graphify-Labs/graphify>, package `graphifyy` 0.9.95, docs
  <https://docs.graphify.com>. The `main` branch README is stale; the `v8` branch matches the
  0.9.95 sdist.
- Comparable tools reviewed and not trialled further: `code-review-graph` (SQLite store, same
  AST-only premise), and the Graphify MCP server, which exposes the same graph to agents and
  therefore inherits every limitation above.
- The `.gitignore` Graphify block added on 2026-10-02 stays: it is harmless and describes where a
  future evaluation would write its artifacts.

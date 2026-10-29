# opengist

Self-hosted gist service (Gist clone). Every gist is a real git repository; clone and push over HTTP. Deployed in the **utility** cluster, namespace `git-system`, next to forgejo.

## architecture

- Single container: `ghcr.io/thomiceli/opengist:1.15.2@sha256:7edc91273ee7d10a17406da8a08c803158baaff984c39b789c1313473d068f21` via `bjw-s-labs` **app-template 5.2.1** (repo standard, not the official chart).
- HTTP on port `6157`. The builtin SSH git server is **disabled** (`OG_SSH_GIT_ENABLED=disabled`) — no port 2222 anywhere.
- State on PVC `opengist-data` (5Gi, RWO, `local-nvme`): SQLite db, git repos, bleve search index, all under `/opengist`. Single replica, strategy `Recreate`.
- Writable: `/opengist` (PVC) and `/tmp` (emptyDir). Everything else is a read-only rootfs, non-root uid/gid 1000.
- `https://gist.techtales.io` → Envoy (`envoy/networking/https`) → `opengist:6157`. DNS via `external-dns/unifi`.
- Probes use `GET /healthcheck` (returns 503 when the DB ping fails).
- Backups: volsync ReplicationSource every 15 min, restic → MinIO (`s3.techtales.io`).

## initial configuration

Completed at first deploy (2026-10-07). The pieces, and where each lives:

| piece                                   | where                                                                                                                                                            |
| --------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `SECRET_KEY`                            | OpenBao `infra/kubernetes/utility/git-system/opengist` — generated once with `openssl rand -base64 32`. Rotating it invalidates sessions and MFA recovery codes. |
| `OIDC_CLIENT_ID` / `OIDC_CLIENT_SECRET` | same OpenBao key — values come from the Pocket ID application                                                                                                    |
| Pocket ID application                   | `id.techtales.io`, redirect URI `https://gist.techtales.io/oauth/openid-connect/callback`, group claim `groups`                                                  |
| volsync restic keys                     | OpenBao `infra/kubernetes/utility/volsync/opengist-data` (`RESTIC_REPOSITORY`, `RESTIC_PASSWORD`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)                  |

The `opengist` ExternalSecret renders the OpenBao keys into env-style names
(`SECRET_KEY` → `OG_SECRET_KEY`, `OIDC_CLIENT_ID` → `OG_OIDC_CLIENT_KEY`,
`OIDC_CLIENT_SECRET` → `OG_OIDC_SECRET`) and the container consumes it with `envFrom`.
The reloader annotation restarts the pod when the secret rotates.

**Admin bootstrap:** the _first user created_ becomes admin. Sign in via Pocket ID first, before anyone else.

**Admin panel toggles** (`/-/admin-panel` → configuration; these are runtime settings stored in SQLite, not env vars):

- Require login to browse: **on** — the core switch; all browsing, search, gist pages, raw files and clones require a session.
- Allow individual gists without login: **off** — no anonymous exception links.
- Disable user signup: **on** — accounts come only via OIDC.
- Disable login form: **on** — force OIDC-only login.

## using git

- Create a gist in the web UI (or `git push` to init — the repo URL is offered per gist).
- Clone/push over HTTP only: `https://gist.techtales.io/<user>/<gist>.git`.
- Git does **not** use Pocket ID SSO. Create an access token at `/-/settings/access-tokens`; git prompts for username (your opengist username) and password (the token).
- Anonymous clone does not work — a consequence of internal-only mode (intended, see below).

## design decisions

- **No gateway-level auth on purpose.** The repo's `envoy-pocketid` component must NOT be attached to this
  HTTPRoute: its ext-auth reads only the `pocketid-token` cookie, so git clients and API-token requests would
  get 401. Opengist is its own OIDC client; all routes pass the edge unauthenticated and the app enforces auth
  per request.
- **Internal-only instance.** No anonymous browsing or raw downloads. Flipping "Allow individual gists without login" back on is the escape hatch for link-sharing — a runtime toggle, no redeploy.
- **No SSH git server (v1).** HTTP covers clone/push; skipping 2222 avoids host-key management and an extra Service/route. Revisit only if SSH becomes a hard requirement.
- **app-template over the official chart.** Repo standardizes on app-template 5.2.1; kubesearch survey (Oct 2026) found 4/4 real-world k8s deployments use app-template, 0/4 the official 0.x chart.
- **SQLite + RWO + `Recreate`.** Single writer; RollingUpdate can wedge a rollout on the volume. Matches all four surveyed deployments.
- **OIDC admin mapping.** `OG_OIDC_GROUP_CLAIM_NAME=groups` + `OG_OIDC_ADMIN_GROUP=admins` — same Pocket ID group forgejo uses, so forgejo admins are also opengist admins. Namespace a dedicated group later if that is too broad.
- **stdout-only logs.** Upstream default (`stdout,file`) also writes `opengist.log` onto the data PVC without rotation; `OG_LOG_OUTPUT=stdout` removed the file copy (PR #10900).
- **Secrets via OpenBao + ExternalSecrets** — utility-cluster convention (SOPS stays reserved for bootstrap material).

## troubleshooting

- `curl -I https://gist.techtales.io` returns **404 on `/`** for HEAD — expected: `/` registers GET only
  (upstream registers HEAD just for `/healthcheck`). Use `curl -s -o /dev/null -w '%{http_code}'` for GET; an
  anonymous GET `/` redirects to `/-/all` (browse mode) or to `/-/login` once "Require login to browse" is on.
- `GET /` is the _new-gist_ page upstream — the browse page is `/-/all`, login is `/-/login` (reserved routes moved under `/-/` in v1.15).
- ExternalSecret `SecretSyncedError` with "map has no entry for key X" → a key name in the OpenBao entry is misspelled, not the path.
- Pod stuck `CreateContainerConfigError` with "secret opengist not found" → the ExternalSecret is red; fix the OpenBao keys first.

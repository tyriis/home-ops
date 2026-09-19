# tokentelemetry

Local dashboard for AI coding-agent token and cost usage (<https://tokentelemetry.com>).

The backend reads each agent's log directory from a read-only host mount and keeps its own
state (`history.db`, summaries, budgets, settings) on the `tokentelemetry_data` volume.

## Layout

- `compose.yaml`: shared compose definition (pull-only GHCR images, default loopback ports)
- `docker/purple/tokentelemetry/compose.yaml`: purple target instance (opencode log mount)
- `docker/purple/tokentelemetry/.env`: purple non-secret vars

## Ports

Both published ports bind to `127.0.0.1` only, which is the security boundary. They are declared
in the shared compose.

- UI: `http://localhost:13000` (host 13000 → container 3000)
- API: `http://localhost:18000` (host 18000 → container 8000)

The API host port is fixed at 18000: CI bakes `NEXT_PUBLIC_API_PORT=18000` into the published
frontend bundle, and the browser derives the API URL from the current hostname plus that port.
Changing the API host port requires rebuilding the frontend image.

No `TT_AUTH_TOKEN` is set, matching the native loopback-only experience. If these ports are ever
published beyond loopback, set `TT_AUTH_TOKEN` via a host `env_file` and publish the backend
without the `127.0.0.1` prefix — see <https://tokentelemetry.com/docs/configuration/remote-access/>.

## Agent mounts

Each host declares the agent log directories it actually has, as read-only binds in its shim
(`/root/.claude`, `/root/.codex`, `/root/.local/share/opencode`, …). Purple mounts opencode only.

# pocket-id

## overview

Pocket ID is a simple OIDC provider for authenticating users of internal web
applications. It is deployed on the utility cluster via Flux
(`kubernetes/utility/apps/secops/pocket-id`).

## backups

Pocket ID stores its data in a SQLite database at `/app/data/pocket-id.db`.
A Litestream sidecar (defined in `litestream.yaml`) continuously replicates
the database to the `litestream` bucket on `s3.techtales.io` under
`pocket-id/pocket-id.db`. The sidecar validates the replica every hour.

## runbooks

- [Litestream: Non-Contiguous LTX Files](runbooks/litestream-non-contiguous-ltx-files.md) —
  diagnose and repair broken or diverged Litestream replica chains for the
  Pocket ID database.

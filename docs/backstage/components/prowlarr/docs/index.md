# Media - Prowlarr

Prowlarr manages indexers for the *arr suite. It gives indexer access to Sonarr, Radarr
and Bazarr.

- App: `kubernetes/main/apps/media/prowlarr`
- URL: `https://prowlarr.techtales.io`
- Image: `ghcr.io/home-operations/prowlarr`

Setup matches [Sonarr](../../sonarr/docs/index.md). The environment prefix is `PROWLARR__`.
Prowlarr has no MediaCover cache. The indexer definition cache is `Definitions/`.

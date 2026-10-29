# Media - Bazarr

Bazarr manages subtitles for the Sonarr and Radarr library.

- App: `kubernetes/main/apps/media/bazarr`
- URL: `https://bazarr.techtales.io`
- Image: `ghcr.io/home-operations/bazarr`

Bazarr is a Python app. It reads config from `DYNACONF_` environment variables, not from a Servarr config.xml.

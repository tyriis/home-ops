# scanservjs

### configure authentik outpost

scanservjs has no build in user auth. In order to be able to authenticate the access to the scanner web frontend we will setup an authentik outpost as auth proxy ingress.

**Limitation**: unfortunatly this can not be made (or i did not found the solution to setup) with a gitops workflow. There we need to configure the outpost manually via the web ui of authentik.

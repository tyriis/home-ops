# Redacted secret reference

## Copyright

copyed this file from [here](https://raw.githubusercontent.com/Truxnell/home-cluster/2aeeeb3f9ab2fc8a60f7712cd3925b73526b5cfe/k8s/manifests/core/system-monitoring/thanos/readme.md). Thank you Truxnell <3

## thanos-objectstore-secret

This is a redacted copy of the Thanos secret for reference.

Note that the s3 URL does not have http(s) appended - this is implied by setting the `insecure` flag to true or false.

```yaml
# yamllint disable
apiVersion: v1
kind: Secret
metadata:
  name: thanos-objstore-secret
  namespace: system-monitoring
stringData:
  objstore.yml: |-
    type: s3
    config:
      bucket: <bucket>
      endpoint: <s3 url - no http/https>
      access_key: <s3 key>
      secret_key: <s3 secret>
      insecure: true
```

<!-- markdownlint-disable MD033 -->
<!-- markdownlint-disable MD046 -->
<!-- markdownlint-disable MD013 -->

# System: talos-flux

## Installation and Configuration

<!-- This section describes the steps required to install and configure the system, including any prerequisites and dependencies. -->

### Bootstrap Talos

<!-- This section describes the steps required to bootstrap the talos nodes, including any prerequisites and dependencies. -->

To inital install Talos Linux on the NUC devices, I currently use an USB thumb drive. For further details check the official [getting-started guide](https://www.talos.dev/v1.5/introduction/getting-started/)

### Setup SOPS key

<!-- This section describes the steps required to configure and use sops with age, including any prerequisites and dependencies. -->

I am currently using SOPS with age.

for further informations on how to create your first key check [the sops repo](https://github.com/getsops/sops)

### prepare talos config

[talhelper](https://github.com/budimanjojo/talhelper) should be available on the system

```bash
talhelper -v
```

<details><summary>Output</summary>

```bash
➜ talhelper version 1.9.3
```

<details>

Generate secrets with talhelper:

```bash
talhelper gensecret > talsecret.sops.yaml
```

Encrypt the generated secrets with sops:

```bash
sops -e -i talsecret.sops.yaml
```

Create the `talconfig.yaml`, check [examples](https://github.com/budimanjojo/talhelper).

Generate the talos configuration files:

```bash
talhelper genconfig
```

<details><summary>Output</summary>

```bash
➜ task talos:config
task: [talos:config] talhelper genconfig
[SOPS]   WARN[0000] Found possibly unencrypted comment in file. This is to be expected if the file being decrypted was created with an older version of SOPS.  comment=" yamllint disable"
generated config for talos01 in ./clusterconfig/talos-flux-talos01.yaml
generated config for talos02 in ./clusterconfig/talos-flux-talos02.yaml
generated config for talos03 in ./clusterconfig/talos-flux-talos03.yaml
generated config for talos04 in ./clusterconfig/talos-flux-talos04.yaml
generated client config in ./clusterconfig/talosconfig
generated .gitignore file in ./clusterconfig/.gitignore
```

</details>

You should have the following folder structure now:

```console
.
├── clusterconfig
│   ├── .gitignore
│   ├── talos-flux-talos01.yaml
│   ├── talos-flux-talos02.yaml
│   ├── talos-flux-talos03.yaml
│   ├── talos-flux-talos04.yaml
│   └── talosconfig
├── talconfig.yaml
└── talsecret.sops.yaml
```

### first node (control-plane)

Download [talos][talos-url]

Flash with a tool like [etcher][etcher-url]

Boot the 1st node from usb drive.

!!! note

    Assure the IP on the 1st node matches the configuration from your configuration

On your workstation run:

```bash
talosctl apply-config --insecure \
   --nodes 192.168.1.51 \
   --file clusterconfig/talos-flux-talos01.yaml
```

<details><summary>Output</summary>

```bash
TODO: add command output
```

</details>

Bootstrap the control-plane

```bash
talosctl bootstrap --nodes 192.168.1.51
```

### kubeapi access

In order to be able to access the kubernetes cluster api, run:

```bash
talosctl kubeconfig \
   --talosconfig=infra/talos/clusterconfig/talosconfig \
   --nodes 192.168.1.51 \
   --endpoints 192.168.1.51 \
   --force
```

The kubeconfig should be created and you should be able to access the cluster with the following command:

```bash
kubectl get nodes
```

<details><summary>Output</summary>

```bash
NAME      STATUS   ROLES           AGE    VERSION
talos01   Ready    control-plane   12s    v1.26.3
```

</details>

### more nodes

Lets add the other 3 nodes to our cluster:

Boot the 2nd node from usb drive.

!!! note

    Assure the IP on the 2nd node matches the configuration from your configuration

On your workstation run:

```bash
talosctl apply-config --insecure \
   --nodes 192.168.1.52 \
   --file clusterconfig/talos-flux-talos02.yaml
```

Repeat the steps for node 3 and 4

```bash
talosctl apply-config --insecure \
   --nodes 192.168.1.53 \
   --file clusterconfig/talos-flux-talos03.yaml
```

```bash
talosctl apply-config --insecure \
   --nodes 192.168.1.54 \
   --file clusterconfig/talos-flux-talos04.yaml
```

Lets check our nodes:

```bash
kubectl get nodes
```

<details><summary>Output</summary>

```bash
NAME      STATUS   ROLES           AGE    VERSION
talos01   Ready    control-plane   6m     v1.26.3
talos02   Ready    control-plane   4m     v1.26.3
talos03   Ready    control-plane   2m     v1.26.3
talos04   Ready    <none>          9s     v1.26.3
```

</details>

### Install metrics server

Create the following file:

```yaml linenums="1" title="metrics-server/kustomization.yaml"
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
helmCharts:
  - name: metrics-server
    repo: https://kubernetes-sigs.github.io/metrics-server
    version: 3.8.4
    releaseName: metrics-server
    namespace: kube-system
    valuesFile: values.yaml
commonAnnotations:
  meta.helm.sh/release-name: metrics-server
  meta.helm.sh/release-namespace: kube-system
commonLabels:
  app.kubernetes.io/managed-by: Helm
```

!!! note

    For the latest release version check the repo!

Create the values file:

```yaml linenums="1" title="metrics-server/values.yaml"
---
metrics:
  enabled: false
serviceMonitor:
  enabled: false
```

Render and apply the manifests:

```bash
kubectl kustomize --enable-helm metrics-server | kubectl apply -f -
```

### Install kubelet-csr-approver

Create the following file:

```yaml linenums="1" title="kubelet-csr-approve/kustomization.yaml"
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
helmCharts:
  - name: kubelet-csr-approver
    repo: https://postfinance.github.io/kubelet-csr-approver
    version: 1.0.0
    releaseName: kubelet-csr-approver
    namespace: kube-system
    valuesFile: values.yaml
commonAnnotations:
  meta.helm.sh/release-name: kubelet-csr-approver
  meta.helm.sh/release-namespace: kube-system
commonLabels:
  app.kubernetes.io/managed-by: Helm
```

!!! note

    For the latest release version check the repo!

Create the values file:

```yaml linenums="1" title="kubelet-csr-approve/values.yaml"
---
providerRegex: |
  ^(talos-flux)$
```

Render and apply the manifests:

```bash
kubectl kustomize --enable-helm kubelet-csr-approver | kubectl apply -f -
```

### Install flux

<!-- This section provides detailed instructions on how to install flux, including how to perform specific tasks and how to navigate the system's user interface. -->

## User Manual

<!-- This section provides detailed instructions on how to use the system, including how to perform specific tasks and how to navigate the system's user interface. -->

### Troubleshooting Guide

<!-- This section provides information on common problems that users may encounter when using the system, along with instructions on how to resolve these issues. -->

### Maintenance and Support

<!-- This section provides information on how to maintain and support the system, including how to perform regular backups, how to troubleshoot issues, and how to contact support if needed. -->

### Appendix

<!-- This section may include additional information, such as technical diagrams, code samples, or other supplementary material that may be useful to users or developers. -->

<!-- Overall, system documentation should provide a comprehensive and detailed reference guide for users, developers, and other stakeholders who need to understand and work with the system. -->

[talos-url]: https://github.com/siderolabs/talos/releases
[etcher-url]: https://etcher.balena.io/

<!--
## something

## something else

??? success
   Content.

??? warning classes
   Content.

::uml:: format="png" classes="uml myDiagram" alt="My super diagram placeholder" title="My super diagram" width="300px" height="300px"
  Goofy ->  MickeyMouse: calls
  Goofy <-- MickeyMouse: responds
::end-uml::

```yaml linenums="1" title="test.yaml" hl_lines="2 3"
test:
   a: 123
   b: 213
```

:fontawesome-regular-face-laugh-wink:

:octicons-heart-fill-24:{.heart}

Lorem ipsum[^1] dolor sit amet, consectetur adipiscing elit.[^2]

!!! note

   Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla et euismod
   nulla. Curabitur feugiat, tortor non consequat finibus, justo purus auctor
   massa, nec semper lorem quam in massa.

!!! note "Phasellus posuere in sem ut cursus"

   Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla et euismod
   nulla. Curabitur feugiat, tortor non consequat finibus, justo purus auctor
   massa, nec semper lorem quam in massa.

:fontawesome-regular-face-laugh-wink:

!!! note

   Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla et euismod
   nulla. Curabitur feugiat, tortor non consequat finibus, justo purus auctor
   massa, nec semper lorem quam in massa.

!!! note "Phasellus posuere in sem ut cursus"

   Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla et euismod
   nulla. Curabitur feugiat, tortor non consequat finibus, justo purus auctor
   massa, nec semper lorem quam in massa.

!!! note

   Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla et euismod
   nulla. Curabitur feugiat, tortor non consequat finibus, justo purus auctor
   massa, nec semper lorem quam in massa.

!!! note "Phasellus posuere in sem ut cursus"

   Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla et euismod
   nulla. Curabitur feugiat, tortor non consequat finibus, justo purus auctor
   massa, nec semper lorem quam in massa.

[^1]: Lorem ipsum dolor sit amet, consectetur adipiscing elit.

[^2]:
    Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla et euismod
    nulla. Curabitur feugiat, tortor non consequat finibus, justo purus auctor
    massa, nec semper lorem quam in massa.
-->

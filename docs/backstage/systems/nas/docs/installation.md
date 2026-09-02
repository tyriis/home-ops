<!-- markdownlint-disable MD033 -->
<!-- markdownlint-disable MD046 -->
<!-- markdownlint-disable MD013 -->

# System: nas

## Installation and Configuration

<!-- This section describes the steps required to install and configure the system, including any prerequisites and dependencies. -->

### Bootstrap Talos

<!-- This section describes the steps required to bootstrap the talos nodes, including any prerequisites and dependencies. -->

To inital install Talos Linux on the NUC devices, I currently use an USB thumb drive. For further details check the official [getting-started guide](https://docs.siderolabs.com/talos/v1.11/getting-started/getting-started/)

### Setup SOPS key

<!-- This section describes the steps required to configure and use sops with age, including any prerequisites and dependencies. -->

I am currently using SOPS with age.

for further informations on how to create your first key check [the sops repo](https://github.com/getsops/sops) and [the age repo](https://github.com/FiloSottile/age)

```bash
mkdir -p ~/.config/age && age-keygen >> ~/.config/age/keys.txt
```

### prepare talos config

[talhelper](https://github.com/budimanjojo/talhelper) should be available on the system

```bash
talhelper -v
```

<details><summary>Output</summary>

```bash
➜ talhelper version 1.9.3
```

</details>

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
talhelper genconfig
generated config for nas01 in ./clusterconfig/nas-nas01.yaml
generated config for nas02 in ./clusterconfig/nas-nas02.yaml
generated client config in ./clusterconfig/talosconfig
generated .gitignore file in ./clusterconfig/.gitignore
```

</details>

You should have the following folder structure now:

```console
.
├── clusterconfig
│   ├── .gitignore
│   ├── nas-nas01.yaml
│   ├── nas-nas02.yaml
│   └── talosconfig
├── talconfig.yaml
└── talsecret.sops.yaml
```

### first node (control-plane)

Download [Talos Linux](https://github.com/siderolabs/talos/releases)

Flash with a tool like [etcher](https://etcher.balena.io/)

Boot the 1st node from usb drive.

!!! note

    Assure the IP on the 1st node matches the configuration from your configuration

On your workstation run:

```bash
talosctl apply-config --insecure \
  --nodes 192.168.100.11 \
  --file clusterconfig/nas-nas01.yaml
```

Assure your TALCONFIG env variable is set

```bash
env | grep TALOSCONFIG
```

<details><summary>Output</summary>

```bash
TALOSCONFIG=/home/nils/projects/tyriis/home-ops/talos/nas/clusterconfig/talosconfig
```

</details>

Bootstrap the control-plane

```bash
talosctl bootstrap --nodes 192.168.100.11
```

### kubeapi access

In order to be able to access the kubernetes cluster api, run:

```bash
talosctl kubeconfig \
  --nodes 192.168.100.11 \
  --force
```

The kubeconfig should be created and you should be able to access the cluster with the following command:

```bash
kubectl get nodes
```

<details><summary>Output</summary>

```bash
NAME    STATUS     ROLES           AGE   VERSION
nas01   NotReady   control-plane   64s   v1.34.2
```

</details>

### more nodes

Lets add the other node to our cluster:

Boot the 2nd node from usb drive.

!!! note

    Assure the IP on the 2nd node matches the configuration from your configuration

On your workstation run:

```bash
talosctl apply-config --insecure \
  --nodes 192.168.100.12 \
  --file clusterconfig/nas-nas02.yaml
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
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
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
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
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

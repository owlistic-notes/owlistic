---
sidebar_position: 2
---

# Kubernetes Installation (Recommended)

## Prerequisites

Before installation, ensure you have:

- Read the [System Requirements](system-requirements.md)
- A running Kubernetes cluster
- [Helm](https://helm.sh) installed locally

## Kubernetes/Helm Installation

Owlistic supports deployment on Kubernetes using Helm. Follow these steps to install [Owlistic helm chart](https://github.com/owlistic-notes/helm-charts) on your Kubernetes cluster.

### Step 1: Add the Owlistic Helm Repository

```bash
helm repo add owlistic https://owlistic-notes.github.io/helm-charts
helm repo update
```

### Step 2: Install Using Helm

```bash
# Create a values file (values.yaml) for your configuration
helm install owlistic owlistic/owlistic -f values.yaml
```

Example `values.yaml`:

```yaml
rserver:
  enabled: true
  service:
    enabled: true
    type: ClusterIP
    port: 8080
  persistence:
    data:
      enabled: true
      existingClaim: <your-persistent-volume-claim-name>
  env:
    DB_HOST: postgresql
    DB_PORT: 5432
    DB_NAME: owlistic
    DB_USER: owlistic
    DB_PASSWORD: owlistic
    BROKER_ADDRESS: nats:4222

app:
  enabled: true
  service:
    enabled: true
    type: ClusterIP
    port: 80

postgresql:
  enabled: true
  global:
    postgresql:
      auth:
        username: owlistic
        password: owlistic
        database: owlistic

nats:
  enabled: true
  config:
    jetstream:
      enabled: true
      fileStore:
        enabled: true
        pvc:
          enabled: false
          size: 512Mi
          storageClassName: "-"
```

### Step 3: Verify the Installation

```bash
kubectl get pods -l app.kubernetes.io/name=owlistic
kubectl get services -l app.kubernetes.io/name=owlistic
```

## Post-Installation

After installation:
- The backend should be running on port 8080
- The frontend should be accessible on port 80
- Visit `http://your-server` to access the web interface

## Troubleshooting

If you encounter any issues during installation, please refer to the [Troubleshooting](../troubleshooting/common-issues.md) section for assistance.

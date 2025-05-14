---
sidebar_position: 2
---

# Kubernetes (Recommended)

Owlistic is a Go-based application that can be deployed in several ways. Choose the method that best suits your environment and requirements.

## Prerequisites

Before installation, ensure you have:

- Read the [System Requirements](system-requirements.md)
- Set up PostgreSQL and Kafka (required for storage and real-time synchronization)

## Kubernetes/Helm Installation

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
replicaCount: 2

backend:
  image:
    repository: ghcr.io/owlistic-notes/owlistic
    tag: main-arm64
    pullPolicy: Always

frontend:
  image:
    repository: ghcr.io/owlistic-notes/owlistic-app
    tag: main-arm64
    pullPolicy: Always

service:
  backend:
    type: ClusterIP
    port: 8080
  frontend:
    type: ClusterIP
    port: 80

environment:
  APP_PORT: 8080
  DB_HOST: postgres-service
  DB_PORT: 5432
  DB_USER: admin
  DB_PASSWORD: admin
  DB_NAME: postgres
  KAFKA_BROKER: kafka-service:9092

resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 500m
    memory: 512Mi
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

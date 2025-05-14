---
sidebar_position: 2
---

# Kubernetes (Recommended)

Owlistic is a Go-based application that can be deployed in several ways. Choose the method that best suits your environment and requirements.

## Prerequisites

Before installation, ensure you have:

- Read the [System Requirements](system-requirements.md)
- Set up PostgreSQL and Kafka (required for storage and real-time synchronization)

### Step 1: Create Docker Compose File

Create a file named `docker-compose.yml`:

```yaml
version: '3.8'

services:
  owlistic:
    image: ghcr.io/owlistic-notes/owlistic:latest
    ports:
      - "8080:8080"
    depends_on:
      - postgres
      - kafka
    environment:
      - APP_PORT=8080
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_USER=admin
      - DB_PASSWORD=admin
      - DB_NAME=postgres
      - KAFKA_BROKER=kafka:9092
  owlistic-app:
    image: ghcr.io/owlistic-notes/owlistic-app:latest
    ports:
      - "80:80"
    depends_on:
      - owlistic
  postgres:
    image: postgres:15
    environment:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: admin
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
  kafka:
    image: bitnami/kafka:3
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      ALLOW_PLAINTEXT_LISTENER: yes
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092
      KAFKA_LISTENERS: PLAINTEXT://0.0.0.0:9092
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT
    ports:
      - "9092:9092"
    depends_on:
      - zookeeper

  zookeeper:
    image: bitnami/zookeeper:3
    environment:
      ALLOW_ANONYMOUS_LOGIN: yes
    ports:
      - "2181:2181"

volumes:
  postgres_data:
```

### Step 2: Start the Services

```bash
docker-compose up -d
```

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

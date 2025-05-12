# Installation Guide

Owlistic is a Go-based application that can be deployed in several ways. Choose the method that best suits your environment and requirements.

## Prerequisites

Before installation, ensure you have:

- Read the [System Requirements](system-requirements.md)
- Set up PostgreSQL and Kafka (required for storage and real-time synchronization)

## Binary Installation

### Step 1: Download the Binary

```bash
# For Linux (amd64)
curl -LO https://github.com/owlistic-notes/owlistic/releases/latest/download/owlistic-linux-amd64
chmod +x owlistic-linux-amd64

# For macOS (amd64)
curl -LO https://github.com/owlistic-notes/owlistic/releases/latest/download/owlistic-darwin-amd64
chmod +x owlistic-darwin-amd64

# For Windows (amd64)
# Download from: https://github.com/owlistic-notes/owlistic/releases/latest
```

### Step 2: Configure Environment Variables

Set the required environment variables:

```bash
export DB_HOST=localhost
export DB_PORT=5432
export DB_USER=admin
export DB_PASSWORD=admin
export DB_NAME=postgres
export KAFKA_BROKER=localhost:9092
```

### Step 3: Run the Application

```bash
# Start the backend application
./owlistic-linux-amd64

# Separately, serve the frontend (if using the UI separately)
# See UI setup documentation
```

## Docker Installation

### Using Pre-built Images

```bash
# Pull the backend image
docker pull daviderutigliano/owlistic:main-arm64

# Pull the frontend image
docker pull daviderutigliano/owlistic-ui:main-arm64

# Run the backend
docker run -d \
  --name owlistic \
  -p 8080:8080 \
  -e DB_HOST=postgres \
  -e DB_PORT=5432 \
  -e DB_USER=admin \
  -e DB_PASSWORD=admin \
  -e DB_NAME=postgres \
  -e KAFKA_BROKER=kafka:9092 \
  daviderutigliano/owlistic:main-arm64

# Run the frontend
docker run -d \
  --name owlistic-ui \
  -p 80:80 \
  daviderutigliano/owlistic-ui:main-arm64
```

Note: The above commands assume you have PostgreSQL and Kafka running and accessible.

## Docker Compose Installation (Recommended)

### Step 1: Create Docker Compose File

Create a file named `docker-compose.yml`:

```yaml
version: '3.8'

services:
  owlistic:
    image: daviderutigliano/owlistic:main-arm64
    ports:
      - "8080:8080"
    depends_on:
      - postgres
      - kafka
    environment:
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_USER=admin
      - DB_PASSWORD=admin
      - DB_NAME=postgres
      - KAFKA_BROKER=kafka:9092
  owlistic-ui:
    image: daviderutigliano/owlistic-ui:main-arm64
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
    repository: daviderutigliano/owlistic
    tag: main-arm64
    pullPolicy: Always

frontend:
  image:
    repository: daviderutigliano/owlistic-ui
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

## Building from Source

If you prefer to build from source:

```bash
# Clone the repository
git clone https://github.com/owlistic-notes/owlistic.git
cd owlistic

# Build the backend
cd src/backend
go build -o owlistic

# Build the frontend
cd ../frontend
npm install
npm run build
```

## Post-Installation

After installation:
- The backend should be running on port 8080
- The frontend should be accessible on port 80
- Visit `http://your-server` to access the web interface

## Troubleshooting

If you encounter any issues during installation, please refer to the [Troubleshooting](../troubleshooting/common-issues.md) section for assistance.
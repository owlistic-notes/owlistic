---
sidebar_position: 3
---

# Docker Compose Installation (Recommended)

## Prerequisites

Before installation, ensure you have:

- Read the [System Requirements](system-requirements.md)
- Docker installed on your system

## Steps

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
      - APP_ORIGINS=http://owlistic*,http://owlistic-app*
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

## Post-Installation

After installation:
- The backend should be running on port 8080
- The frontend should be accessible on port 80
- Visit `http://your-server` to access the web interface

## Troubleshooting

If you encounter any issues during installation, please refer to the [Troubleshooting](../troubleshooting/common-issues.md) section for assistance.

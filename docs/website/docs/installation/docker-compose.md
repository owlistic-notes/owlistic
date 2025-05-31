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
      - nats
    environment:
      - APP_ORIGINS=http://owlistic*,http://owlistic-app*
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_USER=admin
      - DB_PASSWORD=admin
      - DB_NAME=postgres
      - BROKER_ADDRESS=nats:4222

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

  nats:
    image: nats
    command:
      - --http_port
      - "8222"
      - -js
      - -sd
      - /var/lib/nats/data
    ports:
     - "4222:4222"
     - "8222:8222"
    volumes:
      - nats_data:/var/lib/nats/data

volumes:
  postgres_data:
  nats_data:
```

### Step 2: Start the Services

```bash
docker-compose up -d
```

## Post-Installation

After installation:
- The server should be running on port 8080
- The app should be accessible on port 80
- Visit `http://your-server` to access the web interface

## Troubleshooting

If you encounter any issues during installation, please refer to the [Troubleshooting](../troubleshooting/common-issues.md) section for assistance.

---
sidebar_position: 4
---

# Docker Installation

## Prerequisites

Before installation, ensure you have:

- Read the [System Requirements](system-requirements.md)
- Docker installed on your system
- Set up PostgreSQL and NATS (either in docker or on your local machine)

## Steps

### Step 1: Set up PostgreSQL and NATS containers in Docker (if not already running)

```yaml
version: '3.8'

services:
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

### Step 2.1 Using Pre-built Images

```bash
# Pull the backend image
docker pull ghcr.io/owlistic-notes/owlistic:latest

# Pull the frontend image
docker pull ghcr.io/owlistic-notes/owlistic-app:latest
```

```bash
# Run the backend
docker run -d \
  --name owlistic \
  -p 8080:8080 \
  -e APP_PORT=8080 \
  -e DB_HOST=postgres \
  -e DB_PORT=5432 \
  -e DB_USER=admin \
  -e DB_PASSWORD=admin \
  -e DB_NAME=postgres \
  -e BROKER_ADDRESS=nats:4222 \
  ghcr.io/owlistic-notes/owlistic:latest

# Run the frontend
docker run -d \
  --name owlistic-app \
  -p 80:80 \
  ghcr.io/owlistic-notes/owlistic-app:latest
```

Note: The above commands assume you have PostgreSQL and NATS running and accessible respectively at `postgres:5432` and `nats:4222`.

### Step 2.2: Building from Source

```bash

# Build the backend image
docker build -t owlistic:latest .

# Build the frontend image
docker build -t owlistic-app:latest .

# Run the backend container
docker run -d \
  --name owlistic \
  -p 8080:8080 \
  -e APP_PORT=8080 \
  -e DB_HOST=postgres \
  -e DB_PORT=5432 \
  -e DB_NAME=owlistic \
  -e DB_USER=admin \
  -e DB_PASSWORD=admin \
  -e BROKER_ADDRESS=nats:4222 \
  owlistic

# Run the frontend container
docker run -d \
  --name owlistic-app \
  -p 80:80 \
  owlistic-app
```

Note: The above commands assume you have PostgreSQL and NATS running and accessible respectively at `postgres:5432` and `nats:4222`.

## Post-Installation

After installation:
- The backend should be running on port 8080
- The frontend should be accessible on port 80
- Visit `http://your-server` to access the web interface

## Troubleshooting

If you encounter any issues during installation, please refer to the [Troubleshooting](../troubleshooting/common-issues.md) section for assistance.

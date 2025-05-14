---
sidebar_position: 4
---

# Docker Installation

Owlistic is a Go-based application that can be deployed in several ways. Choose the method that best suits your environment and requirements.

## Prerequisites

Before installation, ensure you have:

- Read the [System Requirements](system-requirements.md)
- Set up PostgreSQL and Kafka (required for storage and real-time synchronization)

## Steps

### Using Pre-built Images

```bash
# Pull the backend image
docker pull ghcr.io/owlistic-notes/owlistic:latest

# Pull the frontend image
docker pull ghcr.io/owlistic-notes/owlistic-app:latest

# Run the backend
docker run -d \
  --name owlistic \
  -p 8080:8080 \
  -e APP_PORT=8080 \
  -e DB_PORT=5432 \
  -e DB_USER=admin \
  -e DB_PASSWORD=admin \
  -e DB_NAME=postgres \
  -e KAFKA_BROKER=kafka:9092 \
  ghcr.io/owlistic-notes/owlistic:latest

# Run the frontend
docker run -d \
  --name owlistic-app \
  -p 80:80 \
  ghcr.io/owlistic-notes/owlistic-app:latest
```

Note: The above commands assume you have PostgreSQL and Kafka running and accessible.

## Post-Installation

After installation:
- The backend should be running on port 8080
- The frontend should be accessible on port 80
- Visit `http://your-server` to access the web interface

## Troubleshooting

If you encounter any issues during installation, please refer to the [Troubleshooting](../troubleshooting/common-issues.md) section for assistance.

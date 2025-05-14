---
sidebar_position: 5
---

# Binary Installation

Owlistic is a Go-based application that can be deployed in several ways. Choose the method that best suits your environment and requirements.

## Prerequisites

Before installation, ensure you have:

- Read the [System Requirements](system-requirements.md)
- Set up PostgreSQL and Kafka (required for storage and real-time synchronization)

## Steps

### Step 1: Download the Binary

```bash
# For Linux (amd64)
curl -LO https://github.com/owlistic-notes/owlistic/releases/latest/download/owlistic
# Make owlistic executable
chmod +x owlistic

curl -L https://github.com/owlistic-notes/owlistic/releases/latest/download/owlistic-app.zip -o owlistic-app.zip
# Extract the UI files
unzip owlistic-app.zip -d owlistic-app
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
./owlistic

# Serve the UI using a simple HTTP server
cd owlistic-app
python3 -m http.server 80
```

## Post-Installation

After installation:
- The backend should be running on port 8080
- The frontend should be accessible on port 80
- Visit `http://your-server` to access the web interface

## Troubleshooting

If you encounter any issues during installation, please refer to the [Troubleshooting](../troubleshooting/common-issues.md) section for assistance.

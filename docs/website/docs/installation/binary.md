---
sidebar_position: 5
---

# Binary Installation

## Prerequisites

Before installation, ensure you have:

- Read the [System Requirements](system-requirements.md)
- Set up PostgreSQL and NATS (required for storage and real-time synchronization)
- [Flutter](https://flutter.dev/docs/get-started/install) installed on your system (required for building the Flutter web app)

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
export APP_ORIGINS=http://localhost*
export DB_HOST=localhost
export DB_PORT=5432
export DB_USER=admin
export DB_PASSWORD=admin
export DB_NAME=postgres
export BROKER_ADDRESS=localhost:9092
```

### Step 3: Run the Application

```bash
# Start the server application
./owlistic

# Serve the UI using a simple HTTP server
cd owlistic-app
flutter run -d <chrome|linux|macos|ios|android>
```

## Post-Installation

After installation:
- The server should be running on port 8080
- The app should be accessible on port 80
- Visit `http://your-server` to access the web interface

## Troubleshooting

If you encounter any issues during installation, please refer to the [Troubleshooting](../troubleshooting/common-issues.md) section for assistance.

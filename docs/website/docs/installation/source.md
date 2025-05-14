---
sidebar_position: 6
---

# Installation

Owlistic is a Go-based application that can be deployed in several ways. Choose the method that best suits your environment and requirements.

## Prerequisites

Before installation, ensure you have:

- Read the [System Requirements](system-requirements.md)
- Set up PostgreSQL and Kafka (required for storage and real-time synchronization)

## Building from Source

If you prefer to build from source:

```bash
# Clone the repository
git clone https://github.com/owlistic-notes/owlistic.git
cd owlistic
```

### Building the backend server

```
# Build the backend
cd src/backend
go build -o owlistic cmd/main.go
```

### Building the Flutter Web UI

To build the frontend Flutter web application:

```bash
# Navigate to the frontend directory
cd src/frontend

# Ensure Flutter dependencies are installed
flutter pub get

# Build the web release
flutter build web --release
```

This will generate the web artifacts in the `build/web` directory, which can be deployed to any web server.

#### Deploying the Web UI

You can deploy the Flutter web build by hosting it locally or using a basic web server:

```bash
# Navigate to the build directory
cd build/web

# Serve using Python's built-in HTTP server (for testing)
python3 -m http.server 80
```

## Post-Installation

After installation:
- The backend should be running on port 8080
- The frontend should be accessible on port 80
- Visit `http://your-server` to access the web interface

## Troubleshooting

If you encounter any issues during installation, please refer to the [Troubleshooting](../troubleshooting/common-issues.md) section for assistance.

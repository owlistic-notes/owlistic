---
sidebar_position: 6
---

# Build From Source

## Prerequisites

Before installation, ensure you have:

- Read the [System Requirements](system-requirements.md)
- Set up PostgreSQL and Kafka (required for storage and real-time synchronization)
- [Flutter](https://flutter.dev/docs/get-started/install) installed on your system (required for building the Flutter web app)

## Building from Source

If you prefer to build from source:

```bash
# Clone the repository
git clone https://github.com/owlistic-notes/owlistic.git
cd owlistic
```

### Step 1: Building the backend server

```
# Build the backend
cd src/backend
go build -o owlistic cmd/main.go
```

### Step 2: Building the Flutter Web UI

To build the frontend Flutter web application:

```bash
# Navigate to the frontend directory
cd src/frontend

# Ensure Flutter dependencies are installed
flutter pub get
```

This will generate the web artifacts in the `build/web` directory, which can be deployed to any web server.


### Step 3: Configure Environment Variables

Set the required environment variables:

```bash
export APP_ORIGINS=http://localhost*
export DB_HOST=localhost
export DB_PORT=5432
export DB_USER=admin
export DB_PASSWORD=admin
export DB_NAME=postgres
export KAFKA_BROKER=localhost:9092
```

### Step 4: Run the Application

```bash
# Start the backend application
cd src/backend
./owlistic

# Run the flutter app
cd src/frontend
flutter run -d <chrome|linux|macos|ios|android>
```

## Post-Installation

After installation:
- The backend should be running on port 8080
- The frontend should be accessible on port 80
- Visit `http://your-server` to access the web interface

## Troubleshooting

If you encounter any issues during installation, please refer to the [Troubleshooting](../troubleshooting/common-issues.md) section for assistance.

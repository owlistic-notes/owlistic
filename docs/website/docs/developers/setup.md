# Setup

Follow the steps below to set up your development environment. 

## Prerequisites

Before you begin, ensure you have the following installed:

- **Go** (version 1.23 or above) for the backend
- **Flutter** (latest stable version) for the frontend
- **Git** (for version control)
- **Docker** and **Docker Compose** (for local deployment with dependencies)
- A code editor of your choice (e.g., Visual Studio Code)

## Cloning the Repository

First, clone the repository to your local machine:

```bash
git clone https://github.com/owlistic-notes/owlistic.git
cd owlistic
```

## Development Workflow

Owlistic consists of two main components:

1. **Backend**: Written in Go
2. **Frontend**: Flutter web application

### Setting Up the Backend

Navigate to the backend directory and build the Go application:

```bash
cd src/backend
go mod download
go build -o build/owlistic cmd/main.go
```

#### Running the Backend

Before running the backend, ensure PostgreSQL and NATS are available. You can use Docker Compose for this:

```bash
# From the project root directory
docker-compose up -d postgres nats
```

Configure environment variables:

```bash
export DB_HOST=localhost
export DB_PORT=5432
export DB_USER=admin
export DB_PASSWORD=admin
export DB_NAME=postgres
export BROKER_ADDRESS=localhost:9092
```

Run the backend server:

```bash
cd src/backend
./build/owlistic
```

The backend should now be running on `http://localhost:8080`.

### Setting Up the Frontend

Navigate to the Flutter frontend directory:

```bash
cd src/frontend
```

Install Flutter dependencies:

```bash
flutter pub get
```

#### Running the Frontend

Start the Flutter web application in development mode:

```bash
flutter run -d chrome
```

This will launch the application in Chrome.

## Making Changes

You can now make changes to the codebase. Here are some guidelines:

- Backend (Go): Changes will require recompilation and restarting the server
- Frontend (Flutter): Many changes will automatically reload in the browser

## Testing Your Changes

Before submitting your contributions, ensure that all tests pass:

```bash
# For backend tests
cd src/backend
go test ./...

# For frontend tests
cd src/frontend
flutter test
```

## Full Development Environment with Docker Compose

For convenience, you can use Docker Compose to run the entire application stack:

```bash
docker-compose up -d
```

This will start PostgreSQL, NATS, and the Owlistic backend and frontend services.

## Submitting Your Changes

Once you are satisfied with your changes, commit them and push to your forked repository:

```bash
git add .
git commit -m "Your descriptive commit message"
git push origin your-branch-name
```

Finally, create a pull request to the main repository for review.

Thank you for contributing to Owlistic!

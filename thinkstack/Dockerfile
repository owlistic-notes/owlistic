# Stage 1: Build the Go backend
FROM golang:1.24-bookworm AS backend-builder

WORKDIR /app

# Copy go.mod and go.sum files
COPY go.mod go.sum /app/

# Download dependencies
RUN go mod download

# Copy the backend source code
COPY ./src/backend /app/

# Build the Go application
RUN go build -v -o thinkstack ./cmd/main.go

# Stage 2: Build the Flutter frontend
FROM flutter/flutter:3.10.5 AS frontend-builder

WORKDIR /frontend

# Copy the Flutter frontend source code
COPY ./src/frontend /frontend

# Build the Flutter web app
RUN flutter build web --release

# Stage 3: Create the final image
FROM nginx:stable-alpine

WORKDIR /app

# Copy the backend binary
COPY --from=backend-builder /app/thinkstack /app/

# Copy the Flutter web build output
COPY --from=frontend-builder /frontend/build/web /usr/share/nginx/html

# Expose the backend port
EXPOSE 8080

# Expose the frontend port (nginx default)
EXPOSE 80

# Start both the backend and nginx
CMD ["/bin/sh", "-c", "/app/thinkstack & nginx -g 'daemon off;'"]

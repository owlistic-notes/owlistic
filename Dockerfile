# Use the official Golang image as the base image
FROM golang:1.24-bookworm as builder

# Set the working directory inside the container
WORKDIR /app

# Copy the source code
COPY ./src/ /app/

# Set the working directory for the backend
WORKDIR /app/backend

# Download dependencies
RUN go mod download

# Build the application
RUN go build -v -o /app/thinkstack ./cmd/main.go

# Use a minimal image for the final stage
FROM debian:bullseye-slim

# Set the working directory inside the container
WORKDIR /app

# Copy the built binary from the builder stage
COPY --from=builder /app .

# Expose the application port
EXPOSE 8080

# Run the application
CMD ["./thinkstack"]

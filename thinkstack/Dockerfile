# Use the official Golang image as the base image
FROM golang:1.24-bookworm as builder

# Set the working directory inside the container
WORKDIR /app

# Copy go.mod and go.sum files
COPY go.mod go.sum /app/

# Download dependencies
RUN go mod download

# Copy the source code
COPY . /app/

# Build the application
RUN go build -v -o thinkstack /app/cmd/main.go

# Use a minimal image for the final stage
FROM debian:bullseye-slim

# Set the working directory inside the container
WORKDIR /app

# Copy the built binary from the builder stage
COPY --from=builder /app .

# Expose the application port
EXPOSE 5000

# Run the application
CMD ["/app/thinkstack"]

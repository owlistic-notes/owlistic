# Use the official Golang image as the base image
FROM --platform=linux/amd64 golang:1.21.4-alpine3.18 AS builder

ENV TARGETARCH=amd64

# Install librdkafka for Kafka client dependencies with Alpine packages
RUN apk add --no-cache \
    gcc \
    g++ \
    libc-dev \
    mold \
    musl-dev \
    cyrus-sasl-dev \
    build-base \
    pkgconf \
    librdkafka-dev \
    git

# Set the working directory inside the container
WORKDIR /app

# Copy go.mod and go.sum files first for better layer caching
COPY ./src/backend/go.mod ./src/backend/go.sum* /app/

# Download dependencies
RUN go mod download

# Copy the rest of the source code
COPY ./src/backend/ /app/

# Build the application with proper linking flags for librdkafka
# Adding -tags musl and removing -m64 flag via CGO_CFLAGS
RUN CGO_ENABLED=1 CGO_LDFLAGS="-lsasl2" \
    GO111MODULE=on GOOS=linux GOARCH=${TARGETARCH} \
    CXX=g++ \
    CC=gcc \
    go build -v -tags musl -ldflags "-w -s" \
    -o /app/thinkstack ./cmd/main.go

# Use a minimal Alpine image for the final stage
FROM alpine:3.19

# Install runtime dependencies - adding more libraries that might be needed
RUN apk add --no-cache \
    librdkafka \
    librdkafka-dev \
    ca-certificates \
    libc6-compat

# Set the working directory inside the container
WORKDIR /app

# Copy the built binary from the builder stage
COPY --from=builder /app/thinkstack ./

# Expose the application port
EXPOSE 8080

# Set the entrypoint to the binary
ENTRYPOINT ["/app/thinkstack"]

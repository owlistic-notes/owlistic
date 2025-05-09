# Use the official Golang image as the base image
FROM --platform=linux/$TARGETARCH golang:1.23.4-alpine AS builder

# Set ARG for platform targeting
ARG TARGETARCH

# Install librdkafka for Kafka client dependencies with Alpine packages
RUN apk add --no-cache \
    gcc \
    musl-dev \
    cyrus-sasl-dev

# Set the working directory inside the container
WORKDIR /app

# Copy go.mod and go.sum files first for better layer caching
COPY ./go.mod ./go.sum ./

# Download dependencies
RUN go mod download

# Copy the rest of the source code
COPY . .

# Build the application with proper linking flags for librdkafka
# Adding -tags musl and removing -m64 flag via CGO_CFLAGS
RUN CGO_ENABLED=1 GO111MODULE=on CGO_LDFLAGS="-lsasl2" \
    GOOS=linux GOARCH=${TARGETARCH} \
    go build -v -tags musl -ldflags "-w -s" \
    -o /app/thinkstack ./cmd/main.go

# Use a minimal Alpine image for the final stage
FROM --platform=linux/$TARGETARCH alpine:3.19

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

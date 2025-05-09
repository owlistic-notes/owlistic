# First stage: Build the Flutter web app
FROM debian:latest AS build

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*

# Set up Flutter
# NOTE: You may want to pin a specific version tag instead of master for reproducible builds
RUN git clone https://github.com/flutter/flutter.git -b stable /flutter
ENV PATH="/flutter/bin:$PATH"

# Verify flutter installation
RUN flutter doctor

# Set working directory
WORKDIR /app

# Copy the Flutter project files
# Update this if your Flutter project is in a subdirectory
COPY . .

# Configure Flutter for web
RUN flutter config --enable-web

# Get Flutter packages
RUN flutter pub get

# Initialize web project (creates index.html if missing)
RUN flutter create --platforms=web .

# Build the web app with warning suppressed
RUN flutter build web --release

# Second stage: Serve the app with Nginx
FROM nginx:alpine

# Copy the build output to replace the default nginx contents
COPY --from=build /app/build/web /usr/share/nginx/html

# If you have a custom nginx config, uncomment the following line
# COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port 80
EXPOSE 80

# Start Nginx server
CMD ["nginx", "-g", "daemon off;"]

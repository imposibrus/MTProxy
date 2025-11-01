# Use Ubuntu as base image for building
FROM ubuntu:22.04 AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    libssl-dev \
    zlib1g-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /src

# Copy source code
COPY . .

# Build the application
RUN make clean && make

# Runtime image
FROM ubuntu:22.04

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libssl3 \
    zlib1g \
    curl \
    ca-certificates \
    xxd \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*

# Create user for running the proxy
RUN useradd -r -s /bin/false mtproxy

# Create directories
RUN mkdir -p /opt/mtproxy /etc/mtproxy && \
    chown -R mtproxy:mtproxy /etc/mtproxy

# Set working directory for the binary
WORKDIR /opt/mtproxy

# Copy binary from builder stage
COPY --from=builder /src/objs/bin/mtproto-proxy /opt/mtproxy/

# Make binary executable
RUN chmod +x /opt/mtproxy/mtproto-proxy

# Copy startup script
COPY start.sh /opt/mtproxy/start.sh
RUN chmod +x /opt/mtproxy/start.sh

# Expose ports
EXPOSE 443 8888

# Volume for configuration files
VOLUME ["/etc/mtproxy"]

# Set entrypoint
ENTRYPOINT ["/opt/mtproxy/start.sh"]

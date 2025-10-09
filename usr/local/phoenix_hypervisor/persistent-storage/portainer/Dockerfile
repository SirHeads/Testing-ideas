# Use Ubuntu as the base image for building
FROM ubuntu:latest AS builder

# Install necessary packages
RUN apt-get update && \
    apt-get install -y ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

# Copy the custom CA certificate into the image
COPY phoenix_ca.crt /usr/local/share/ca-certificates/phoenix_ca.crt

# Update the CA certificates store
RUN update-ca-certificates

# --- Final stage ---
FROM portainer/portainer-ce:latest

# Copy the updated CA certificates from the builder stage
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Expose Portainer ports (optional, but good practice)
EXPOSE 9000
EXPOSE 9443

# Command to run Portainer (default command from original image)
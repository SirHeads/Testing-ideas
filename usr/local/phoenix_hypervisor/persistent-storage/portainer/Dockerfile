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

# It's crucial to also update the certificates within the final image context
# It's not necessary to run update-ca-certificates in the final stage,
# as the certificate store is already updated in the builder stage.
# The portainer/portainer-ce image is distroless and does not have a shell.

# Expose Portainer ports
EXPOSE 9000
EXPOSE 9443

# Add a healthcheck to verify Portainer is running
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-check-certificate -q -O - https://localhost:9443/api/status | grep -q 'Version' || exit 1

# Command to run Portainer (default command from original image)
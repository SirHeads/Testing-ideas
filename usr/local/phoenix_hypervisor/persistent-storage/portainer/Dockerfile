# Use the Alpine version of Portainer-CE, which includes a shell and ca-certificates package
FROM portainer/portainer-ce:alpine

# Install the ca-certificates package, which provides the update-ca-certificates command
RUN apk add --no-cache ca-certificates

# Copy the custom CA certificate into the correct directory for Alpine's update-ca-certificates script
COPY phoenix_ca.crt /usr/local/share/ca-certificates/phoenix_ca.crt

# Run the command to update the certificate store. This is the crucial step that makes
# the Go runtime inside the container trust our custom CA.
RUN update-ca-certificates

# Expose Portainer ports (inherited from base image, but good practice to declare)
EXPOSE 9000
EXPOSE 9443

# The HEALTHCHECK and CMD are inherited from the portainer/portainer-ce:alpine base image,
# so we don't need to redefine them. This keeps the Dockerfile clean and focused on our customization.
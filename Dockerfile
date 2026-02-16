FROM docker:24-dind

# Install required tools
RUN apk add --no-cache \
    curl \
    bash \
    git

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/

# Install helm
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install k3d
RUN curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# Copy project files
COPY wiki-service /app/wiki-service
COPY wiki-chart /app/wiki-chart
COPY k3d-config.yaml /app/k3d-config.yaml
COPY k3d-lb-values.yaml /app/k3d-lb-values.yaml
COPY entrypoint.sh /app/entrypoint.sh

RUN chmod +x /app/entrypoint.sh

WORKDIR /app

# Expose port 8080
EXPOSE 8080

# Use entrypoint script to start everything
ENTRYPOINT ["/app/entrypoint.sh"]

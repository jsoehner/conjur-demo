# syntax=docker/dockerfile:1
FROM alpine:3.20

LABEL org.opencontainers.image.title="conjur-demo" \
      org.opencontainers.image.description="CyberArk Conjur Policy-Controlled Certificate Lifecycle and mTLS Demo Runner" \
      org.opencontainers.image.source="https://github.com/jsoehner/conjur-demo" \
      org.opencontainers.image.licenses="Apache-2.0"

# Install runtime tools required to orchestrate the demo
RUN apk add --no-cache \
    bash \
    curl \
    openssl \
    netcat-openbsd \
    jq \
    python3 \
    docker-cli \
    docker-cli-compose

WORKDIR /app

# Copy orchestration assets
COPY policy/ ./policy/
COPY scripts/ ./scripts/
COPY docker-compose.hub.yml ./docker-compose.hub.yml
COPY init.sh ./init.sh
COPY run_docker.sh ./run_docker.sh
COPY docker-run.sh ./docker-run.sh

RUN chmod +x init.sh run_docker.sh docker-run.sh scripts/*.sh scripts/*.py 2>/dev/null || true

ENTRYPOINT ["/bin/bash", "/app/run_docker.sh"]
CMD ["up"]

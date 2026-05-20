FROM python:3.9-slim

RUN groupadd -r appgroup && useradd -r -g appgroup appuser

RUN apt-get update && \
    apt-get install -y --no-install-recommends openssl curl && \
    rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir requests

COPY mtls-client/app.py /app.py
COPY issuer-client/sidecar.sh /sidecar.sh

RUN chmod +x /sidecar.sh && \
    chown appuser:appgroup /app.py /sidecar.sh && \
    mkdir /certs && \
    chown appuser:appgroup /certs

USER appuser

# Run both the sidecar and the app
CMD /sidecar.sh & python -u /app.py

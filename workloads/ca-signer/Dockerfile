FROM python:3.9-slim

RUN groupadd -r appgroup && useradd -r -g appgroup appuser

ARG OSS_PIP_INDEX_URL=""
ARG OSS_PIP_TRUSTED_HOST=""
RUN apt-get update && \
    apt-get install -y --no-install-recommends openssl && \
    rm -rf /var/lib/apt/lists/* && \
    if [ -n "$OSS_PIP_INDEX_URL" ]; then \
      pip install --no-cache-dir --index-url "$OSS_PIP_INDEX_URL" ${OSS_PIP_TRUSTED_HOST:+--trusted-host "$OSS_PIP_TRUSTED_HOST"} requests; \
    else \
      pip install --no-cache-dir requests; \
    fi

COPY ca-signer/signer.py /signer.py

RUN chown appuser:appgroup /signer.py && \
    mkdir -p /tmp/ca && \
    chown -R appuser:appgroup /tmp/ca

WORKDIR /

USER appuser

CMD ["python", "-u", "/signer.py"]

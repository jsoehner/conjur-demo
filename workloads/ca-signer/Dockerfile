FROM python:3.9-slim

RUN groupadd -r appgroup && useradd -r -g appgroup appuser

RUN apt-get update && \
    apt-get install -y --no-install-recommends openssl && \
    rm -rf /var/lib/apt/lists/* && \
    pip install requests

COPY ca-signer/signer.py /signer.py

RUN chown appuser:appgroup /signer.py && \
    mkdir -p /tmp/ca && \
    chown -R appuser:appgroup /tmp/ca

WORKDIR /

USER appuser

CMD ["python", "-u", "/signer.py"]

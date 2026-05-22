FROM python:3.9-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends openssl && \
    rm -rf /var/lib/apt/lists/*

COPY ca-signer/signer.py /signer.py

WORKDIR /

CMD ["python", "-u", "/signer.py"]

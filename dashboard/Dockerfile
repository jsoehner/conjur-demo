FROM python:3.11-slim

RUN groupadd -r appgroup && useradd -r -g appgroup appuser

RUN apt-get update && \
    apt-get install -y --no-install-recommends openssl docker.io && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /dashboard

COPY requirements.txt .
ARG OSS_PIP_INDEX_URL=""
ARG OSS_PIP_TRUSTED_HOST=""
RUN if [ -n "$OSS_PIP_INDEX_URL" ]; then \
      pip install --no-cache-dir --index-url "$OSS_PIP_INDEX_URL" ${OSS_PIP_TRUSTED_HOST:+--trusted-host "$OSS_PIP_TRUSTED_HOST"} -r requirements.txt; \
    else \
      pip install --no-cache-dir -r requirements.txt; \
    fi

COPY app.py .
COPY static/ static/

RUN chown -R appuser:appgroup /dashboard

EXPOSE 5000

USER appuser

CMD ["python", "-u", "app.py"]

FROM python:3.11-slim

RUN groupadd -r appgroup && useradd -r -g appgroup appuser

RUN apt-get update && \
    apt-get install -y --no-install-recommends openssl docker.io && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /dashboard

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .
COPY static/ static/

RUN chown -R appuser:appgroup /dashboard

EXPOSE 5000

USER appuser

CMD ["python", "-u", "app.py"]

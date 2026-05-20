FROM python:3.11-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends openssl docker.io && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /dashboard

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .
COPY static/ static/

EXPOSE 5000

CMD ["python", "-u", "app.py"]

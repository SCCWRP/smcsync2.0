FROM python:3.10-slim-bookworm

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    libpq-dev \
 && rm -rf /var/lib/apt/lists/*

RUN pip install --upgrade pip

RUN mkdir /app
WORKDIR /app
COPY requirements.txt .

RUN pip install -r requirements.txt


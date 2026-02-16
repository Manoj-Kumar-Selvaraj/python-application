# -------- Base Image --------
FROM python:3.10-slim

# Prevent Python from writing .pyc files
ENV PYTHONDONTWRITEBYTECODE=1
# Ensure stdout/stderr are unbuffered
ENV PYTHONUNBUFFERED=1

# Set working directory
WORKDIR /app

# Install minimal system dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy dependency definition first (Docker layer caching)
COPY pyproject.toml uv.lock* ./

# Install dependencies
RUN pip install --upgrade pip \
    && pip install --no-cache-dir .

# Copy application source
COPY app ./app

# Create non-root user
RUN useradd -m -u 1000 appuser
USER 1000

# Expose application port
EXPOSE 8000

# Start Gunicorn with ONE worker (Kubernetes handles scaling)
CMD ["gunicorn", "-k", "uvicorn.workers.UvicornWorker", "-w", "1", "-b", "0.0.0.0:8000", "app.main:app"]
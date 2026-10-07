FROM python:3.12-slim

WORKDIR /app
# Hide the *_created helper series so /metrics stays readable
ENV PROMETHEUS_DISABLE_CREATED_SERIES=True PYTHONUNBUFFERED=1
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .
RUN useradd --no-create-home app
USER app

EXPOSE 8000
HEALTHCHECK --interval=10s --timeout=3s CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health').status==200 else 1)"
CMD ["python", "app.py"]

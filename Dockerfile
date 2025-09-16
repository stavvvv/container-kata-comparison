FROM python:3.8-slim
WORKDIR /app

# Copy the function code
COPY function_app.py /app/function_app.py
COPY app.py /app/app.py

# Install system dependencies
RUN apt-get update && apt-get install -y \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Create directories for sample images and temporary files
RUN mkdir -p /app/images /tmp

# Download a sample image for testing
RUN wget -q https://raw.githubusercontent.com/opencv/opencv/master/samples/data/lena.jpg -O /app/images/sample.jpg

# Install Python dependencies
RUN pip install --no-cache-dir azure-functions Pillow azure-storage==0.36.0 Flask prometheus-flask-exporter gunicorn

# Expose port for HTTP trigger
EXPOSE 8080

# Run the Flask application with Gunicorn
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--threads", "2", "--timeout", "0", "--log-level", "debug", "app:app"]



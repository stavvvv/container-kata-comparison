FROM python:3.8-slim

WORKDIR /app

# Copy the function code - since we're in the float_operation directory already
COPY __init__.py /app/function_app.py

# Create a wrapper to simulate Azure Functions runtime
RUN echo 'import math\nfrom time import time\nfrom function_app import float_operations\nimport http.server\nimport socketserver\nfrom urllib.parse import urlparse, parse_qs\n\nclass FunctionHandler(http.server.SimpleHTTPRequestHandler):\n    def do_GET(self):\n        self.send_response(200)\n        self.send_header("Content-type", "text/plain")\n        self.end_headers()\n        \n        # Parse query parameters\n        query = urlparse(self.path).query\n        params = parse_qs(query)\n        \n        # Get N parameter with default value of 1000000\n        N = int(params.get("N", ["1000000"])[0])\n        \n        # Call the function from __init__.py\n        latency = float_operations(N)\n        \n        self.wfile.write(str(latency).encode())\n        return\n\nPORT = 8080\nwith socketserver.TCPServer(("", PORT), FunctionHandler) as httpd:\n    print(f"Serving at port {PORT}")\n    httpd.serve_forever()' > app.py

# Install dependencies
RUN pip install --no-cache-dir azure-functions

# Expose port for HTTP trigger
EXPOSE 8080

# Run the application
CMD ["python", "app.py"]

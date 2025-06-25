from flask import Flask, request, jsonify
import os
import base64
from function_app import image_processing

app = Flask(__name__)

@app.route('/', methods=['GET'])
def process_image():
    """
    Process image with various transformations and return latency only
    Query parameters:
    - image_path: Path to input image (default: /app/images/sample.jpg)
    """
    try:
        # Get image path parameter
        image_path = request.args.get('image_path', '/app/images/sample.jpg')
        
        # Check if image exists
        if not os.path.exists(image_path):
            return f"Error: Image not found at {image_path}", 404
        
        # Get the file name from the path
        file_name = os.path.basename(image_path)
        
        # Process the image and measure latency
        latency, path_list = image_processing(file_name, image_path)
        
        # Return just the latency as plain text (optimized for performance testing)
        return str(latency), 200, {'Content-Type': 'text/plain'}
            
    except Exception as e:
        error_msg = f"Error processing image: {str(e)}"
        print(error_msg)
        return error_msg, 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=True)

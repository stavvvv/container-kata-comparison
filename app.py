from flask import Flask, request, Response
import os
from function_app import image_processing, flip, rotate, filter, gray_scale, resize
from prometheus_flask_exporter import PrometheusMetrics
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST
from PIL import Image
import io
from time import time

app = Flask(__name__) 
metrics = PrometheusMetrics(app)

@app.route('/metrics')
@metrics.do_not_track()
def metrics_endpoint():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

@app.route('/', methods=['GET'])
@metrics.do_not_track()
@metrics.histogram('image_processing_duration_seconds', 'GET duration')
def process_image():
    try:
        image_path = request.args.get('image_path', '/app/images/sample.jpg')
        
        if not os.path.exists(image_path):
            return f"Error: Image not found at {image_path}", 404
        
        file_name = os.path.basename(image_path)
        latency, path_list = image_processing(file_name, image_path)
        
        return str(latency), 200, {'Content-Type': 'text/plain'}
            
    except Exception as e:
        error_msg = f"Error processing image: {str(e)}"
        print(error_msg)
        return error_msg, 500

@app.route('/upload', methods=['POST'])
@metrics.histogram('image_processing_post_duration_seconds', 'POST duration')
def process_image_post():
    try:
        if 'image' not in request.files:
            return {'error': 'Missing input image'}, 400
        
        image_file = request.files['image']
        if image_file.filename == '':
            return {'error': 'No file selected'}, 400
        
        # Read image bytes and process in memory
        image_bytes = image_file.read()
        file_name = image_file.filename if image_file.filename else 'uploaded_image.jpg'
        
        start = time()
        image_stream = io.BytesIO(image_bytes)
        with Image.open(image_stream) as image:
            path_list = []
            path_list += flip(image, file_name)
            path_list += rotate(image, file_name)
            path_list += filter(image, file_name)
            path_list += gray_scale(image, file_name)
            path_list += resize(image, file_name)
        
        latency = time() - start
        return str(latency), 200, {'Content-Type': 'text/plain'}
            
    except Exception as e:
        error_msg = f"Error processing image: {str(e)}"
        print(error_msg)
        return error_msg, 500

if __name__ == '__main__':  
    app.run(debug=True, host='0.0.0.0', port=8080)


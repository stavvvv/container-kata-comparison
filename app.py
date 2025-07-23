from flask import Flask, request, jsonify, Response
import os
from function_app import image_processing
from prometheus_flask_exporter import PrometheusMetrics
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST

app = Flask(__name__)

metrics = PrometheusMetrics(app)

@app.route('/metrics')
@metrics.do_not_track()
def metrics_endpoint():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

@app.route('/', methods=['GET'])
@metrics.histogram('image_processing_duration_seconds', 'Image processing duration')
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

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=True)


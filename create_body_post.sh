#!/bin/bash
IMAGE_PATH="$1"
TIMESTAMP="$2"
OUTPUT_BODY="body.txt"
FILENAME=$(basename "$IMAGE_PATH")
BOUNDARY="boundary"

if [ ! -f "$IMAGE_PATH" ]; then
    echo "Error: Image file '$IMAGE_PATH' not found!"
    exit 1
fi

if [ -z "$TIMESTAMP" ]; then
    TIMESTAMP=$(date +%s.%N)
    echo "No timestamp provided, using current: $TIMESTAMP"
else
    if [ "$TIMESTAMP" = "now" ]; then
        TIMESTAMP=$(date +%s.%N)
        echo "Using current timestamp: $TIMESTAMP"
    fi
fi

echo "Creating multipart form data..."
echo "Image: $IMAGE_PATH"
echo "Timestamp: $TIMESTAMP"

{
    # Image field first (as a file upload)
    printf -- "--%s\r\n" "$BOUNDARY"
    printf "Content-Disposition: form-data; name=\"image\"; filename=\"%s\"\r\n" "$FILENAME"
    printf "Content-Type: image/jpeg\r\n"
    printf "\r\n"
    cat "$IMAGE_PATH"
    printf "\r\n"
    
    # Timestamp field second (as a file upload, as expected by Flask app)
    printf -- "--%s\r\n" "$BOUNDARY"
    printf "Content-Disposition: form-data; name=\"timestamp\"; filename=\"timestamp.txt\"\r\n"
    printf "Content-Type: text/plain\r\n"
    printf "\r\n"
    printf "%s\r\n" "$TIMESTAMP"
    
    printf -- "--%s--\r\n" "$BOUNDARY"
} > "$OUTPUT_BODY"

echo "Created multipart body file: $OUTPUT_BODY"
echo "File size: $(wc -c < "$OUTPUT_BODY") bytes"

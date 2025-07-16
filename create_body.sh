#!/bin/bash
IMAGE_PATH="$1"
OUTPUT_BODY="body.txt"
FILENAME=$(basename "$IMAGE_PATH")
BOUNDARY="boundary"

[ -f "$IMAGE_PATH" ] || exit 1;

# Create proper multipart body
{
  printf -- "--%s\r\n" "$BOUNDARY"
  printf "Content-Disposition: form-data; name=\"image\"; filename=\"%s\"\r\n" "$FILENAME"
  printf "Content-Type: image/jpeg\r\n"
  printf "\r\n"
  cat "$IMAGE_PATH"
  printf "\r\n"
  printf -- "--%s--\r\n" "$BOUNDARY"
} > "$OUTPUT_BODY"

echo "Created body file: $OUTPUT_BODY"

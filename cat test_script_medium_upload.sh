#!/bin/bash

# Create target files for POST requests
echo -e "POST http://147.102.13.62:31397/\nContent-Type: multipart/form-data; boundary=boundary\n@body.txt" > container_upload_targets.txt
echo -e "POST http://147.102.13.62:30885/\nContent-Type: multipart/form-data; boundary=boundary\n@body.txt" > kata_upload_targets.txt

# Function to run vegeta + perf simultaneously
run_test() {
    local container_type=$1
    local targets_file=$2
    local rate=$3
    local perf_output=$4

    echo "Testing $container_type at $rate req/s..."

    # Start perf monitoring in background
    sudo perf stat -e cycles,instructions,context-switches,cpu-migrations,page-faults,cache-references,cache-misses -a -o "$perf_output" sleep 300 &
    PERF_PID=$!

    # Wait a moment for perf to start
    sleep 2

    # Run vegeta attack
    vegeta attack -targets="$targets_file" -rate="$rate" -duration=5m | vegeta report

    # Wait for perf to finish
    wait $PERF_PID

    echo "Completed $container_type at $rate req/s - perf data saved to $perf_output"
}

# Test rates
RATES=(4 8 12 16 20)

# Run tests for each rate
for rate in "${RATES[@]}"; do
    echo "=========================================="
    echo "Testing rate: $rate req/s"
    echo "=========================================="

    # Test Standard Container
    run_test "Standard Container" "container_upload_targets.txt" "$rate" "c_medium_upload_${rate}.txt"

    # Short cooldown after Standard test
    sleep 120

    # Test Kata Container  
    run_test "Kata Container" "kata_upload_targets.txt" "$rate" "k_medium_upload_${rate}.txt"

    # Longer cooldown after Kata test
    sleep 120

    echo ""
done

# Summary
echo "=========================================="
echo "All tests completed!"
echo "=========================================="
echo "Generated files:"
for rate in "${RATES[@]}"; do
    echo "  c_medium_upload_${rate}.txt - Standard container at ${rate} req/s"
    echo "  k_medium_upload_${rate}.txt - Kata container at ${rate} req/s"
done


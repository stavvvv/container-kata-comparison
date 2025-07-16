#!/bin/bash

# Function to run vegeta + perf simultaneously
run_test() {
    local container_type=$1
    local targets_file=$2
    local rate=$3
    local perf_output=$4
    
    echo "Testing $container_type at $rate req/s..."
    
    # Start perf monitoring in background
    sudo perf stat -e cycles,instructions,context-switches,cpu-migrations,page-faults,cache-references,cache-misses -a -o $perf_output sleep 300 &
    PERF_PID=$!
    
    # Wait a moment for perf to start
    sleep 2
    
    # Run vegeta attack
    vegeta attack -targets=$targets_file -rate=$rate -duration=5m | vegeta report
    
    # Wait for perf to finish
    wait $PERF_PID
    
    echo "Completed $container_type at $rate req/s - perf data saved to $perf_output"
}

# Test rates - up to 30 req/s
RATES=(5 10 15 20 25)

# Run tests for each rate
for rate in "${RATES[@]}"; do
    echo "=========================================="
    echo "Testing rate: $rate req/s"
    echo "=========================================="
    
    # Test Standard Container
    run_test "Standard Container" "container_upload_targets.txt" $rate "in_c_small_${rate}.txt"
    
    # Short cooldown after Standard test
    sleep 120
    
    # Test Kata Container  
    run_test "Kata Container" "kata_upload_targets.txt" $rate "in_k_small_${rate}.txt"
    
    # Longer cooldown after Kata test (before next rate)
    sleep 120
    
    echo ""
done

echo "=========================================="
echo "All tests completed!"
echo "=========================================="
echo "Generated files:"
for rate in "${RATES[@]}"; do
    echo "  in_c_small_${rate}.txt - Standard container at ${rate} req/s"
    echo "  in_k_small_${rate}.txt - Kata container at ${rate} req/s"
done

#!/bin/bash

RATES=(15 20 25 30 35)
DURATION="5m"

echo "Starting load tests with dynamic pod deployment:"
echo "Rates: ${RATES[@]} RPS"
echo "Duration: ${DURATION} each"
echo ""

# Function to wait for pod to be ready
wait_for_pod() {
    local app_label=$1
    echo "Waiting for pod with label app=$app_label to be ready..."
    kubectl wait --for=condition=ready pod -l app=$app_label --timeout=300s
    if [ $? -eq 0 ]; then
        echo "Pod is ready!"
    else
        echo "Pod failed to become ready within timeout"
        exit 1
    fi
}

# Create results directory
mkdir -p results
cd results

for rate in "${RATES[@]}"; do
    echo "=== Testing ${rate} RPS ==="
    
    # ===== REGULAR CONTAINER TEST =====
    echo "$(date): Applying Regular Container deployment..."
    kubectl apply -f ../container-deployment.yaml
    
    # Wait for pod to be ready
    wait_for_pod "image-processing-container"
    
    # Additional wait to ensure service is fully ready
    sleep 30
    
    # Verify pod is running
    echo "Pod status:"
    kubectl get pods | grep image-processing-container
    
    echo "$(date): Starting perf monitoring for Regular Container..."
    sudo perf stat -e cycles,instructions,context-switches,cpu-migrations,page-faults,cache-references,cache-misses -a -o regular_${rate}rps_perf.txt sleep 300 &
    PERF_PID=$!
    sleep 2  # Wait for perf to start
    
    echo "$(date): Testing Regular Container at ${rate} RPS..."
    vegeta attack -targets=../container_targets.txt -rate=${rate} -duration=${DURATION} -output=regular_${rate}rps.bin
    
    # Stop perf monitoring
    sudo kill $PERF_PID 2>/dev/null
    wait $PERF_PID 2>/dev/null
    echo "$(date): Regular container attack completed"
    
    # Wait 1 minute before deleting pod to observe post-test behavior
    echo "Waiting 1 minute before deleting pod..."
    sleep 60
    
    echo "$(date): Deleting Regular Container deployment..."
    kubectl delete -f ../container-deployment.yaml
    
    # Wait for pod to be fully deleted and system to stabilize
    echo "Waiting for pod to be deleted and system to stabilize..."
    sleep 120
    
    # Extended cooldown between container types to ensure clean baseline
    echo "Waiting for complete system reset..."
    sleep 180
    
    # ===== KATA CONTAINER TEST =====
    echo "$(date): Applying Kata Container deployment..."
    kubectl apply -f ../kata-deployment.yaml
    
    # Wait for pod to be ready
    wait_for_pod "image-processing-kata"
    
    # Additional wait to ensure service is fully ready
    sleep 30
    
    # Verify pod is running
    echo "Pod status:"
    kubectl get pods | grep image-processing-kata
    
    echo "$(date): Starting perf monitoring for Kata Container..."
    sudo perf stat -e cycles,instructions,context-switches,cpu-migrations,page-faults,cache-references,cache-misses -a -o kata_${rate}rps_perf.txt sleep 300 &
    PERF_PID=$!
    sleep 2  # Wait for perf to start
    
    echo "$(date): Testing Kata Container at ${rate} RPS..."
    vegeta attack -targets=../kata_targets.txt -rate=${rate} -duration=${DURATION} -output=kata_${rate}rps.bin
    
    # Stop perf monitoring
    sudo kill $PERF_PID 2>/dev/null
    wait $PERF_PID 2>/dev/null
    echo "$(date): Kata container attack completed"
    
    # Wait 1 minute before deleting pod to observe post-test behavior
    echo "Waiting 1 minute before deleting pod..."
    sleep 60
    
    echo "$(date): Deleting Kata Container deployment..."
    kubectl delete -f ../kata-deployment.yaml
    
    # Wait for pod to be fully deleted and system to stabilize
    echo "Waiting for pod to be deleted and system to stabilize..."
    sleep 120
    
    # Longer cooldown before next rate (except for the last iteration)
    if [ "$rate" != "35" ]; then
        echo "Longer cooldown before next rate..."
        sleep 120
    fi
    
    echo "Completed ${rate} RPS tests"
    echo ""
done

echo "Generating timing analysis..."
for rate in "${RATES[@]}"; do
    echo "=== Timing Analysis for ${rate} RPS ==="
    
    # Analyze Regular Container timing
    if [ -f "results/regular_${rate}rps_timing.txt" ]; then
        echo "Regular Container - Load/Processing/Total Times:"
        awk '{load+=$1; proc+=$2; total+=$3; n++} END {
            printf "  Avg Load Time: %.4fs\n", load/n
            printf "  Avg Processing Time: %.4fs\n", proc/n  
            printf "  Avg Total Time: %.4fs\n", total/n
            printf "  Load %% of Total: %.1f%%\n", (load/total)*100
            printf "  Processing %% of Total: %.1f%%\n", (proc/total)*100
        }' results/regular_${rate}rps_timing.txt
    fi
    
    # Analyze Kata Container timing
    if [ -f "results/kata_${rate}rps_timing.txt" ]; then
        echo "Kata Container - Load/Processing/Total Times:"
        awk '{load+=$1; proc+=$2; total+=$3; n++} END {
            printf "  Avg Load Time: %.4fs\n", load/n
            printf "  Avg Processing Time: %.4fs\n", proc/n
            printf "  Avg Total Time: %.4fs\n", total/n
            printf "  Load %% of Total: %.1f%%\n", (load/total)*100
            printf "  Processing %% of Total: %.1f%%\n", (proc/total)*100
        }' results/kata_${rate}rps_timing.txt
    fi
    echo ""
done

echo "All tests completed at $(date)"



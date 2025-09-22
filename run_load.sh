#post requests
#!/bin/bash

RATES=(2 4 6 8 10)
DURATION="3m"
IMAGE_FILE="test_image.jpg"

echo "Multi-Rate Container Runtime Performance Comparison"
echo "Rates: ${RATES[@]} RPS" 
echo "Duration: ${DURATION} each"
echo "Image: ${IMAGE_FILE}"
echo ""

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[ERROR] $1"
}

info() {
    echo "[INFO] $1"
}

# Function to wait for pod readiness with extended timeout
wait_for_pod_ready() {
    local app_label=$1
    local endpoint_port=$2
    local max_wait=300
    
    log "Waiting for pod with label app=$app_label to be ready..."
    kubectl wait --for=condition=ready pod -l app=$app_label --timeout=${max_wait}s
    
    if [ $? -eq 0 ]; then
        info "Pod is ready. Waiting additional 30s for full service initialization..."
        sleep 30
        
        # Verify service responds
        info "Testing service responsiveness on port $endpoint_port..."
        for attempt in {1..5}; do
            sleep 5
            if curl -s --max-time 10 "http://127.0.0.1:${endpoint_port}/metrics" > /dev/null; then
                info "Service is responding!"
                return 0
            fi
            echo "Service not responding, attempt $attempt/5..."
            sleep 5
        done
        echo "Service may not be fully ready but continuing..."
        return 0
    else
        error "Pod failed to become ready within timeout"
        kubectl get pods -l app=$app_label
        kubectl describe pod -l app=$app_label
        return 1
    fi
}

# Function to clean up pods completely
cleanup_deployment() {
    local deployment_file=$1
    log "Cleaning up deployment: $deployment_file"
    kubectl delete -f $deployment_file --grace-period=0 --force
    
    # Wait for complete cleanup
    log "Waiting for complete resource cleanup..."
    sleep 45
    
    # Verify no pods remain
    remaining_pods=$(kubectl get pods --no-headers 2>/dev/null | grep -c "image-processing")
    if [ $remaining_pods -gt 0 ]; then
        echo "$remaining_pods pods still remain, waiting longer..."
        sleep 30
    fi
    info "Cleanup completed"
}

# Function to create request body with current timestamp
create_body_with_timestamp() {
    local image_path=$1
    local output_body="body.txt"
    local filename=$(basename "$image_path")
    local boundary="boundary"
    
    if [ ! -f "$image_path" ]; then
        error "Image file '$image_path' not found"
        return 1
    fi
    
    # Get current timestamp in seconds with microsecond precision
    local current_timestamp=$(date +%s.%6N)
    
    # Create proper multipart body with image and timestamp
    {
        # Image field
        printf -- "--%s\r\n" "$boundary"
        printf "Content-Disposition: form-data; name=\"image\"; filename=\"%s\"\r\n" "$filename"
        printf "Content-Type: image/jpeg\r\n"
        printf "\r\n"
        cat "$image_path"
        printf "\r\n"
        
        # Timestamp field
        printf -- "--%s\r\n" "$boundary"
        printf "Content-Disposition: form-data; name=\"timestamp\"; filename=\"timestamp.txt\"\r\n"
        printf "Content-Type: text/plain\r\n"
        printf "\r\n"
        printf "%s" "$current_timestamp"
        printf "\r\n"
        
        # End boundary
        printf -- "--%s--\r\n" "$boundary"
    } > "$output_body"
    
    info "Created body file: $output_body with timestamp: $current_timestamp"
    return 0
}

# Function to extract timing metrics from prometheus output
extract_timing_metrics() {
    local metrics_file=$1
    local container_type=$2
    local rate=$3
    local output_file=$4
    
    echo "" >> $output_file
    echo "TIMING BREAKDOWN ($container_type - ${rate} RPS):" >> $output_file
    
    if [ ! -f "$metrics_file" ]; then
        echo "  Metrics file not found: $metrics_file" >> $output_file
        return
    fi
    
    # Debug: Show what metrics are available
    echo "  Available timing metrics:" >> $output_file
    grep -E "(memory_load|image_parse|image_processing_operations|total_image_processing).*_(sum|count)" "$metrics_file" | head -10 >> $output_file
    
    # Extract timing metrics
    memory_load_sum=$(grep "memory_load_duration_seconds_sum" "$metrics_file" | tail -1 | awk '{print $2}')
    memory_load_count=$(grep "memory_load_duration_seconds_count" "$metrics_file" | tail -1 | awk '{print $2}')
    
    image_parse_sum=$(grep "image_parse_duration_seconds_sum" "$metrics_file" | tail -1 | awk '{print $2}')
    image_parse_count=$(grep "image_parse_duration_seconds_count" "$metrics_file" | tail -1 | awk '{print $2}')
    
    processing_sum=$(grep "image_processing_operations_duration_seconds_sum" "$metrics_file" | tail -1 | awk '{print $2}')
    processing_count=$(grep "image_processing_operations_duration_seconds_count" "$metrics_file" | tail -1 | awk '{print $2}')
    
    total_sum=$(grep "total_image_processing_duration_seconds_sum" "$metrics_file" | tail -1 | awk '{print $2}')
    total_count=$(grep "total_image_processing_duration_seconds_count" "$metrics_file" | tail -1 | awk '{print $2}')
    
    post_sum=$(grep "image_processing_post_duration_seconds_sum" "$metrics_file" | tail -1 | awk '{print $2}')
    post_count=$(grep "image_processing_post_duration_seconds_count" "$metrics_file" | tail -1 | awk '{print $2}')
    
    echo "" >> $output_file
    echo "  Raw metric values:" >> $output_file
    echo "    memory_load_sum: $memory_load_sum, count: $memory_load_count" >> $output_file
    echo "    image_parse_sum: $image_parse_sum, count: $image_parse_count" >> $output_file
    echo "    processing_sum: $processing_sum, count: $processing_count" >> $output_file
    echo "    total_sum: $total_sum, count: $total_count" >> $output_file
    echo "    post_sum: $post_sum, count: $post_count" >> $output_file
    
    # Calculate averages if we have valid data
    echo "" >> $output_file
    echo "  Calculated averages:" >> $output_file
    if [ ! -z "$memory_load_sum" ] && [ ! -z "$memory_load_count" ] && [ "$memory_load_count" != "0" ] && [ "$memory_load_count" != "0.0" ]; then
        if (( $(echo "$memory_load_count > 0" | bc -l 2>/dev/null || echo "0") )); then
            avg=$(echo "scale=6; $memory_load_sum / $memory_load_count" | bc -l 2>/dev/null)
            if [ ! -z "$avg" ]; then
                avg_ms=$(echo "scale=2; $avg * 1000" | bc -l 2>/dev/null)
                echo "    Avg Memory Load Time: ${avg}s (${avg_ms}ms)" >> $output_file
            fi
        fi
    fi
    
    if [ ! -z "$processing_sum" ] && [ ! -z "$processing_count" ] && [ "$processing_count" != "0" ] && [ "$processing_count" != "0.0" ]; then
        if (( $(echo "$processing_count > 0" | bc -l 2>/dev/null || echo "0") )); then
            avg=$(echo "scale=6; $processing_sum / $processing_count" | bc -l 2>/dev/null)
            if [ ! -z "$avg" ]; then
                avg_ms=$(echo "scale=2; $avg * 1000" | bc -l 2>/dev/null)
                echo "    Avg Processing Time: ${avg}s (${avg_ms}ms)" >> $output_file
            fi
        fi
    fi
    
    if [ ! -z "$total_sum" ] && [ ! -z "$total_count" ] && [ "$total_count" != "0" ] && [ "$total_count" != "0.0" ]; then
        if (( $(echo "$total_count > 0" | bc -l 2>/dev/null || echo "0") )); then
            avg=$(echo "scale=6; $total_sum / $total_count" | bc -l 2>/dev/null)
            if [ ! -z "$avg" ]; then
                avg_ms=$(echo "scale=2; $avg * 1000" | bc -l 2>/dev/null)
                echo "    Avg Total Processing Time: ${avg}s (${avg_ms}ms)" >> $output_file
            fi
        fi
    fi
}

# Function to extract JSON response data from vegeta results
extract_json_responses() {
    local vegeta_file=$1
    local output_file=$2
    local container_type=$3
    local rate=$4
    
    echo "" >> $output_file
    echo "FLASK APP RESPONSE ANALYSIS ($container_type - ${rate} RPS):" >> $output_file
    
    # Extract successful responses, decode base64, and parse JSON data
    vegeta encode "$vegeta_file" 2>/dev/null | jq -r '
        select(.code == 200) | 
        .body
    ' | base64 -d 2>/dev/null | jq -r '
        "\(.memory_load_time // "N/A") \(.processing_time // "N/A") \(.request_age_seconds // "N/A") \(.total_image_processing_time // "N/A")"
    ' > /tmp/response_data_${rate}.txt 2>/dev/null
    
    if [ -s /tmp/response_data_${rate}.txt ]; then
        # Calculate averages from response data
        awk 'NF>=3 && $1!="N/A" && $2!="N/A" && $3!="N/A" {
            load+=$1; proc+=$2; age+=$3; total+=$4; n++
        } END {
            if(n>0) {
                printf "  Flask Response Timing Results:\n"
                printf "    Avg Memory Load Time: %.4fs (%.1fms)\n", load/n, (load/n)*1000
                printf "    Avg Processing Time: %.4fs (%.1fms)\n", proc/n, (proc/n)*1000
                printf "    Avg Total Processing Time: %.4fs (%.1fms)\n", total/n, (total/n)*1000
                printf "    Avg Request Age: %.4fs\n", age/n
                printf "    Valid Responses: %d\n", n
            } else {
                print "  No valid timing data found in responses"
            }
        }' /tmp/response_data_${rate}.txt >> $output_file
    else
        echo "  No JSON response data found or responses not in expected format" >> $output_file
    fi
    
    rm -f /tmp/response_data_${rate}.txt
}

# Check dependencies
check_dependencies() {
    log "Checking dependencies..."
    
    for cmd in vegeta kubectl perf jq bc curl; do
        if ! command -v $cmd &> /dev/null; then
            error "$cmd is not installed. Please install it first."
            exit 1
        fi
    done
    
    if [ ! -f "$IMAGE_FILE" ]; then
        error "Test image '$IMAGE_FILE' not found."
        exit 1
    fi
    
    if [ ! -f "container-deployment.yaml" ]; then
        error "container-deployment.yaml not found."
        exit 1
    fi
    
    if [ ! -f "kata-deployment.yaml" ]; then
        error "kata-deployment.yaml not found."
        exit 1
    fi
    
    info "All dependencies check passed"
}

# Create target files
create_targets() {
    log "Creating vegeta target files..."
    
    # Container targets  
    cat > container_upload_targets.txt << EOF
POST http://127.0.0.1:31397/
Content-Type: multipart/form-data; boundary=boundary
@body.txt
EOF

    # Kata targets
    cat > kata_upload_targets.txt << EOF  
POST http://127.0.0.1:30885/
Content-Type: multipart/form-data; boundary=boundary
@body.txt
EOF

    info "Target files created successfully"
}

# Main test execution
main() {
    log "Starting Multi-Rate Container Runtime Performance Comparison..."
    
    check_dependencies
    create_targets
    
    # Create results directory
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    RESULTS_DIR="multi_rate_results_${TIMESTAMP}"
    mkdir -p "$RESULTS_DIR"
    log "Results will be saved to: $RESULTS_DIR"

    for rate in "${RATES[@]}"; do
        echo ""
        echo "==============================================="
        echo "Testing ${rate} RPS"
        echo "==============================================="
        
        # ===== REGULAR CONTAINER TEST =====
        echo ""
        echo "--- Regular Container Test ---"
        log "Deploying regular container..."
        kubectl apply -f container-deployment.yaml
        
        if wait_for_pod_ready "image-processing-container" "31397"; then
            # Create fresh request body
            log "Creating fresh request body..."
            create_body_with_timestamp "$IMAGE_FILE"
            
            log "Starting perf monitoring for Regular Container..."
            sudo perf stat -e cycles,instructions,context-switches,cpu-migrations,page-faults,cache-references,cache-misses,L1-dcache-loads,L1-dcache-load-misses -a -o ${RESULTS_DIR}/regular_${rate}rps_perf.txt sleep 180 &
            PERF_PID=$!
            sleep 2  # Wait for perf to start
            
            log "Starting load test at ${rate} RPS..."
            vegeta attack \
                -targets=container_upload_targets.txt \
                -rate=${rate} \
                -duration=${DURATION} \
                -timeout=30s \
                -output=${RESULTS_DIR}/regular_${rate}rps.bin
            
            # Stop perf monitoring
            sudo kill $PERF_PID 2>/dev/null
            wait $PERF_PID 2>/dev/null
            
            # Collect metrics immediately after vegeta finishes - BEFORE any delays
            log "Load test completed, collecting metrics immediately..."
            curl -s --max-time 10 "http://127.0.0.1:31397/metrics" > ${RESULTS_DIR}/regular_${rate}rps_metrics.txt
            
            # Generate reports
            vegeta report ${RESULTS_DIR}/regular_${rate}rps.bin > ${RESULTS_DIR}/regular_${rate}rps_report.txt
            vegeta report -type=json ${RESULTS_DIR}/regular_${rate}rps.bin > ${RESULTS_DIR}/regular_${rate}rps_report.json
            
            info "Regular container test completed"
            
            # Show quick results
            echo "Quick Results:"
            head -10 ${RESULTS_DIR}/regular_${rate}rps_report.txt
            
            log "Waiting 60 seconds before deleting pod..."
            sleep 60
        else
            error "Regular container failed to become ready"
        fi
        
        # Clean up
        cleanup_deployment "container-deployment.yaml"
        
        # Extended cooldown between container types
        log "Extended system reset between container types (3 minutes)..."
        sleep 180
        
        # ===== KATA CONTAINER TEST =====  
        echo ""
        echo "--- Kata Container Test ---"
        log "Deploying Kata container..."
        kubectl apply -f kata-deployment.yaml
        
        if wait_for_pod_ready "image-processing-kata" "30885"; then
            # Create fresh request body
            log "Creating fresh request body..."
            create_body_with_timestamp "$IMAGE_FILE"
            
            log "Starting perf monitoring for Kata Container..."
            sudo perf stat -e cycles,instructions,context-switches,cpu-migrations,page-faults,cache-references,cache-misses,L1-dcache-loads,L1-dcache-load-misses -a -o ${RESULTS_DIR}/kata_${rate}rps_perf.txt sleep 180 &
            PERF_PID=$!
            sleep 2  # Wait for perf to start
            
            log "Starting load test at ${rate} RPS..."
            vegeta attack \
                -targets=kata_upload_targets.txt \
                -rate=${rate} \
                -duration=${DURATION} \
                -timeout=30s \
                -output=${RESULTS_DIR}/kata_${rate}rps.bin
            
            # Stop perf monitoring
            sudo kill $PERF_PID 2>/dev/null
            wait $PERF_PID 2>/dev/null
            
            # Collect metrics immediately after vegeta finishes - BEFORE any delays
            log "Load test completed, collecting metrics immediately..."
            curl -s --max-time 10 "http://127.0.0.1:30885/metrics" > ${RESULTS_DIR}/kata_${rate}rps_metrics.txt
            
            # Generate reports
            vegeta report ${RESULTS_DIR}/kata_${rate}rps.bin > ${RESULTS_DIR}/kata_${rate}rps_report.txt
            vegeta report -type=json ${RESULTS_DIR}/kata_${rate}rps.bin > ${RESULTS_DIR}/kata_${rate}rps_report.json
            
            info "Kata container test completed"
            
            # Show quick results  
            echo "Quick Results:"
            head -10 ${RESULTS_DIR}/kata_${rate}rps_report.txt
            
            log "Waiting 60 seconds before deleting pod..."
            sleep 60
        else
            error "Kata container failed to become ready"
        fi
        
        # Clean up with longer wait
        cleanup_deployment "kata-deployment.yaml"
        
        # Extended cooldown before next rate
        if [ "$rate" != "${RATES[-1]}" ]; then
            log "Extended cooldown before next rate (2 minutes)..."
            sleep 120
        fi
        
        info "Completed ${rate} RPS comparison"
    done

    echo ""
    echo "==============================================="
    echo "GENERATING COMPREHENSIVE RESULTS"
    echo "==============================================="
    
    # Create comprehensive results summary
    local summary_file="${RESULTS_DIR}/comprehensive_results_summary.txt"
    
    cat > $summary_file << EOF
Multi-Rate Container Runtime Performance Comparison
==================================================
Test Date: $(date)
Rates Tested: ${RATES[@]} RPS
Duration per Test: ${DURATION}
Test Image: ${IMAGE_FILE}
Results Directory: ${RESULTS_DIR}

EOF

    for rate in "${RATES[@]}"; do
        echo "" >> $summary_file
        echo "=======================================" >> $summary_file
        echo "${rate} RPS RESULTS" >> $summary_file
        echo "=======================================" >> $summary_file
        
        # Regular Container Results
        if [ -f "${RESULTS_DIR}/regular_${rate}rps_report.txt" ]; then
            echo "" >> $summary_file
            echo "REGULAR CONTAINER:" >> $summary_file
            cat ${RESULTS_DIR}/regular_${rate}rps_report.txt >> $summary_file
            
            # Add timing breakdown from metrics
            if [ -f "${RESULTS_DIR}/regular_${rate}rps_metrics.txt" ]; then
                extract_timing_metrics "${RESULTS_DIR}/regular_${rate}rps_metrics.txt" "Regular" "${rate}" "$summary_file"
            fi
            
            # Add Flask app response analysis
            if [ -f "${RESULTS_DIR}/regular_${rate}rps.bin" ]; then
                extract_json_responses "${RESULTS_DIR}/regular_${rate}rps.bin" "$summary_file" "Regular" "${rate}"
            fi
            
            # Add perf results
            if [ -f "${RESULTS_DIR}/regular_${rate}rps_perf.txt" ]; then
                echo "" >> $summary_file
                echo "PERFORMANCE COUNTERS (Regular):" >> $summary_file
                cat ${RESULTS_DIR}/regular_${rate}rps_perf.txt >> $summary_file
            fi
        fi
        
        # Kata Container Results
        if [ -f "${RESULTS_DIR}/kata_${rate}rps_report.txt" ]; then
            echo "" >> $summary_file
            echo "KATA CONTAINER:" >> $summary_file
            cat ${RESULTS_DIR}/kata_${rate}rps_report.txt >> $summary_file
            
            # Add timing breakdown from metrics
            if [ -f "${RESULTS_DIR}/kata_${rate}rps_metrics.txt" ]; then
                extract_timing_metrics "${RESULTS_DIR}/kata_${rate}rps_metrics.txt" "Kata" "${rate}" "$summary_file"
            fi
            
            # Add Flask app response analysis
            if [ -f "${RESULTS_DIR}/kata_${rate}rps.bin" ]; then
                extract_json_responses "${RESULTS_DIR}/kata_${rate}rps.bin" "$summary_file" "Kata" "${rate}"
            fi
            
            # Add perf results
            if [ -f "${RESULTS_DIR}/kata_${rate}rps_perf.txt" ]; then
                echo "" >> $summary_file
                echo "PERFORMANCE COUNTERS (Kata):" >> $summary_file
                cat ${RESULTS_DIR}/kata_${rate}rps_perf.txt >> $summary_file
            fi
        fi
        
        # Performance comparison
        if [ -f "${RESULTS_DIR}/regular_${rate}rps_report.json" ] && [ -f "${RESULTS_DIR}/kata_${rate}rps_report.json" ]; then
            regular_mean=$(jq -r '.latencies.mean' ${RESULTS_DIR}/regular_${rate}rps_report.json 2>/dev/null)
            kata_mean=$(jq -r '.latencies.mean' ${RESULTS_DIR}/kata_${rate}rps_report.json 2>/dev/null)
            
            if [ "$regular_mean" != "null" ] && [ "$kata_mean" != "null" ] && [ "$regular_mean" != "" ] && [ "$kata_mean" != "" ]; then
                regular_ms=$(echo "scale=1; $regular_mean / 1000000" | bc -l 2>/dev/null)
                kata_ms=$(echo "scale=1; $kata_mean / 1000000" | bc -l 2>/dev/null)
                
                if [ "$regular_ms" != "" ] && [ "$kata_ms" != "" ] && [ "$regular_ms" != "0" ] && [ "$kata_ms" != "0" ]; then
                    ratio=$(echo "scale=2; $kata_ms / $regular_ms" | bc -l 2>/dev/null)
                    echo "" >> $summary_file
                    echo "PERFORMANCE COMPARISON SUMMARY:" >> $summary_file
                    echo "  Regular Container: ${regular_ms}ms average latency" >> $summary_file
                    echo "  Kata Container: ${kata_ms}ms average latency" >> $summary_file
                    echo "  Performance Ratio: ${ratio}x (Kata vs Regular)" >> $summary_file
                    if [ ! -z "$ratio" ] && (( $(echo "$ratio > 1.0" | bc -l 2>/dev/null || echo "0") )); then
                        overhead=$(echo "scale=1; ($ratio - 1) * 100" | bc -l 2>/dev/null)
                        if [ ! -z "$overhead" ]; then
                            echo "  Kata Overhead: ${overhead}%" >> $summary_file
                        fi
                    fi
                fi
            fi
        fi
    done

    # Generate summary comparison table
    echo "" >> $summary_file
    echo "=======================================" >> $summary_file
    echo "CROSS-RATE COMPARISON SUMMARY" >> $summary_file
    echo "=======================================" >> $summary_file
    echo "" >> $summary_file
    printf "%-8s %-15s %-15s %-15s %-10s\n" "Rate" "Regular (ms)" "Kata (ms)" "Ratio" "Overhead%" >> $summary_file
    printf "%-8s %-15s %-15s %-15s %-10s\n" "----" "-----------" "--------" "-----" "--------" >> $summary_file

    for rate in "${RATES[@]}"; do
        if [ -f "${RESULTS_DIR}/regular_${rate}rps_report.json" ] && [ -f "${RESULTS_DIR}/kata_${rate}rps_report.json" ]; then
            regular_mean=$(jq -r '.latencies.mean' ${RESULTS_DIR}/regular_${rate}rps_report.json 2>/dev/null)
            kata_mean=$(jq -r '.latencies.mean' ${RESULTS_DIR}/kata_${rate}rps_report.json 2>/dev/null)
            
            if [ "$regular_mean" != "null" ] && [ "$kata_mean" != "null" ] && [ "$regular_mean" != "" ] && [ "$kata_mean" != "" ]; then
                regular_ms=$(echo "scale=1; $regular_mean / 1000000" | bc -l 2>/dev/null)
                kata_ms=$(echo "scale=1; $kata_mean / 1000000" | bc -l 2>/dev/null)
                
                if [ "$regular_ms" != "" ] && [ "$kata_ms" != "" ] && [ "$regular_ms" != "0" ] && [ "$kata_ms" != "0" ]; then
                    ratio=$(echo "scale=2; $kata_ms / $regular_ms" | bc -l 2>/dev/null)
                    overhead=$(echo "scale=1; ($ratio - 1) * 100" | bc -l 2>/dev/null)
                    
                    if [ ! -z "$ratio" ] && [ ! -z "$overhead" ]; then
                        printf "%-8s %-15s %-15s %-15s %-10s\n" "${rate}RPS" "$regular_ms" "$kata_ms" "$ratio" "${overhead}%" >> $summary_file
                    fi
                fi
            fi
        fi
    done

    log "All tests completed!"
    log "Results saved to: $RESULTS_DIR"
    info "Main summary: $summary_file"
    
    echo ""
    echo "RESULTS PREVIEW:"
    echo "================"
    head -50 $summary_file
    echo ""
    echo "Individual files available:"
    ls -la $RESULTS_DIR/ | grep -E "\.(txt|json|bin)$" | head -20
}

# Run main function
main "$@"

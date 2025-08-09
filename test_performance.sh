#!/bin/bash

echo "🚀 Starting Performance Test with System Monitoring"
echo "=================================================="

# Start system monitoring in background
echo "📊 Starting system monitors..."

# CPU and Memory monitoring (macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    # Monitor CPU usage
    echo "CPU Usage:" > cpu_monitor.log
    (while true; do 
        top -l 1 -n 0 | grep "CPU usage" >> cpu_monitor.log
        sleep 1
    done) &
    CPU_PID=$!
    
    # Monitor memory usage
    echo "Memory Usage:" > mem_monitor.log
    (while true; do
        vm_stat | grep -E "Pages (free|active|inactive|wired)" >> mem_monitor.log
        echo "---" >> mem_monitor.log
        sleep 1
    done) &
    MEM_PID=$!
    
    # Monitor disk I/O
    echo "Disk I/O:" > disk_monitor.log
    (while true; do
        iostat -d 1 1 >> disk_monitor.log 2>/dev/null
    done) &
    DISK_PID=$!
fi

# Function to cleanup monitoring processes
cleanup() {
    echo ""
    echo "🛑 Stopping monitors..."
    kill $CPU_PID 2>/dev/null
    kill $MEM_PID 2>/dev/null
    kill $DISK_PID 2>/dev/null
    
    # Show summary
    echo ""
    echo "📈 Performance Summary:"
    echo "----------------------"
    echo "Peak CPU Usage:"
    grep "CPU usage" cpu_monitor.log | sort -r | head -1
    
    echo ""
    echo "Memory Statistics:"
    tail -5 mem_monitor.log
    
    echo ""
    echo "Disk I/O Summary:"
    tail -3 disk_monitor.log
}

# Set trap to cleanup on exit
trap cleanup EXIT

echo ""
echo "🧪 Running Zig Extractor Tests..."
echo "================================="

# Test 1: List sessions
echo ""
echo "Test 1: Listing sessions..."
time ./extractor --list

# Test 2: Extract a session
echo ""
echo "Test 2: Extracting a session..."
time ./extractor --extract 1

# Test 3: Search functionality
echo ""
echo "Test 3: Testing search..."
time ./extractor --search "claude"

# Test 4: Run benchmarks
echo ""
echo "Test 4: Running built-in benchmarks..."
time ./extractor --benchmark

echo ""
echo "✅ Tests completed!"
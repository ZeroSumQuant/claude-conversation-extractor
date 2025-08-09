#\!/bin/bash

echo "🔬 Advanced Performance Monitoring for Zig Extractor"
echo "===================================================="

# Check for required tools
if \! command -v dtruss &> /dev/null && [[ "$OSTYPE" == "darwin"* ]]; then
    echo "⚠️  Note: Run with 'sudo' for system call tracing"
fi

# Start time
START_TIME=$(date +%s)

# Memory baseline
echo ""
echo "📊 Memory Baseline:"
vm_stat | grep -E "Pages (free|active|inactive|wired|compressed)"

# Run with time command for basic stats
echo ""
echo "🚀 Running extractor with time measurement..."
echo "-------------------------------------------"
/usr/bin/time -l ./extractor --list 2>&1 | tee extractor_output.log

# Capture end state
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo "📊 Memory After Execution:"
vm_stat | grep -E "Pages (free|active|inactive|wired|compressed)"

# Parse time output
echo ""
echo "⏱️  Performance Metrics:"
echo "----------------------"
grep -E "real|user|sys" extractor_output.log
grep -E "maximum resident set size" extractor_output.log
grep -E "page reclaims|page faults" extractor_output.log

# Check for memory leaks using leaks command
echo ""
echo "🔍 Checking for memory leaks..."
# Get the PID if the process is still running
if pgrep extractor > /dev/null; then
    leaks $(pgrep extractor) 2>/dev/null | grep -E "leaks|LEAK"
else
    echo "Process completed - cannot check for leaks in terminated process"
fi

echo ""
echo "✅ Monitoring complete\! Duration: ${DURATION}s"

#!/bin/bash
# Verification script for Claude TUI build

set -e

echo "======================================"
echo "Claude TUI Build Verification"
echo "======================================"
echo ""

# Check Rust installation
echo "Checking Rust installation..."
if command -v rustc &> /dev/null; then
    rustc --version
    cargo --version
else
    echo "❌ Rust is not installed"
    echo "Please install from: https://rustup.rs/"
    exit 1
fi
echo "✅ Rust is installed"
echo ""

# Check if we can compile
echo "Checking if project compiles..."
if cargo check --quiet 2>/dev/null; then
    echo "✅ Project compiles successfully"
else
    echo "❌ Compilation failed"
    echo "Run 'cargo build' to see detailed errors"
    exit 1
fi
echo ""

# Run tests
echo "Running tests..."
if cargo test --quiet 2>/dev/null; then
    echo "✅ All tests pass"
else
    echo "❌ Some tests failed"
    echo "Run 'cargo test' to see details"
    exit 1
fi
echo ""

# Check Python integration
echo "Checking Python integration..."
if command -v python3 &> /dev/null; then
    python3 --version
    echo "✅ Python is installed"
else
    echo "⚠️  Python not found, but Rust TUI can still be used standalone"
fi
echo ""

# Check maturin
echo "Checking maturin (for Python bindings)..."
if command -v maturin &> /dev/null; then
    maturin --version
    echo "✅ Maturin is installed"
else
    echo "⚠️  Maturin not installed"
    echo "Install with: pip install maturin"
    echo "This is only needed for Python integration"
fi
echo ""

echo "======================================"
echo "Build Verification Complete!"
echo "======================================"
echo ""
echo "Next steps:"
echo "1. Build the project: cargo build --release"
echo "2. For Python integration: maturin develop --release"
echo "3. Run the TUI: cargo run --release"
echo ""
echo "Or use the build script: ./build.sh"
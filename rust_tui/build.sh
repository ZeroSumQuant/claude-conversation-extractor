#!/bin/bash
# Build script for Claude TUI

set -e

echo "Building Claude TUI..."

# Check if Rust is installed
if ! command -v cargo &> /dev/null; then
    echo "Error: Rust is not installed. Please install from https://rustup.rs/"
    exit 1
fi

# Check if maturin is installed
if ! command -v maturin &> /dev/null; then
    echo "Installing maturin..."
    pip install maturin
fi

# Build the Rust library
echo "Building Rust library..."
cargo build --release

# Build Python wheel
echo "Building Python wheel..."
maturin build --release

# Install in development mode (optional)
read -p "Install in development mode? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    maturin develop --release
    echo "Claude TUI installed in development mode!"
fi

echo "Build complete!"
echo ""
echo "To use the TUI:"
echo "  python -m claude_tui.launcher"
echo ""
echo "To install the wheel:"
echo "  pip install target/wheels/*.whl"
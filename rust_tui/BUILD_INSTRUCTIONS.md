# Build Instructions for Claude TUI

## Quick Start

```bash
# 1. Enter the rust_tui directory
cd rust_tui

# 2. Build the project (choose one):
./build.sh              # Interactive build script
cargo build --release   # Manual release build
maturin develop        # For Python integration

# 3. Run the TUI
cargo run --release
```

## Prerequisites

### Required
- **Rust**: 1.70 or later
  - Install from: https://rustup.rs/
  - Verify: `rustc --version`

### Optional (for Python integration)
- **Python**: 3.9 or later
- **Maturin**: `pip install maturin`

## Build Options

### 1. Standalone Rust Binary
```bash
cargo build --release
./target/release/claude-tui
```

### 2. Python Module (with PyO3)
```bash
# Install maturin if not already installed
pip install maturin

# Build and install in development mode
maturin develop --release

# Or build a wheel for distribution
maturin build --release
```

### 3. Using the Build Script
```bash
./build.sh
```
This interactive script will:
- Check for dependencies
- Build the Rust library
- Build Python wheel
- Optionally install in development mode

## Verification

Run the verification script to check everything is set up correctly:
```bash
./verify_build.sh
```

## Troubleshooting

### Compilation Errors

If you encounter compilation errors:

1. **Update Rust**:
   ```bash
   rustup update
   ```

2. **Clean and rebuild**:
   ```bash
   cargo clean
   cargo build --release
   ```

3. **Check dependencies**:
   ```bash
   cargo tree
   ```

### Missing Features

If certain features are missing:

1. **Ensure all features are enabled**:
   ```bash
   cargo build --release --all-features
   ```

2. **Update dependencies**:
   ```bash
   cargo update
   ```

### Python Integration Issues

If Python integration fails:

1. **Check Python version**:
   ```bash
   python --version  # Should be 3.9+
   ```

2. **Reinstall maturin**:
   ```bash
   pip install --upgrade maturin
   ```

3. **Set Python interpreter explicitly**:
   ```bash
   maturin develop --release --interpreter python3
   ```

## Platform-Specific Notes

### macOS
- Ensure Xcode Command Line Tools are installed:
  ```bash
  xcode-select --install
  ```

### Linux
- May need to install development packages:
  ```bash
  # Ubuntu/Debian
  sudo apt-get install build-essential pkg-config
  
  # Fedora/RHEL
  sudo dnf install gcc pkg-config
  ```

### Windows
- Use Visual Studio Build Tools or MinGW
- Run from Git Bash or WSL for best compatibility

## Performance Build

For maximum performance:
```bash
RUSTFLAGS="-C target-cpu=native" cargo build --release
```

## Development Build

For debugging and development:
```bash
cargo build
RUST_LOG=debug cargo run
```

## Cross-Compilation

To build for different platforms:
```bash
# Add target
rustup target add x86_64-unknown-linux-musl

# Build for target
cargo build --release --target x86_64-unknown-linux-musl
```

## Creating Distribution Packages

### PyPI Package
```bash
maturin build --release --strip
twine upload target/wheels/*.whl
```

### Homebrew Formula (macOS)
```bash
cargo build --release
# Create formula with the binary from target/release/
```

### Debian Package (Linux)
```bash
cargo install cargo-deb
cargo deb
```

## Testing

Run all tests:
```bash
cargo test
```

Run benchmarks:
```bash
cargo bench
```

## Documentation

Generate and view documentation:
```bash
cargo doc --open
```
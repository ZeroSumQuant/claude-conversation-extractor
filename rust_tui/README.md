# Claude TUI - High-Performance Terminal User Interface

A blazing-fast, feature-rich terminal user interface for the Claude Conversation Extractor, written in Rust using Ratatui.

## Features

- **6-Page Interface**: Navigate between Home, Browser, Search, Export, Statistics, and Settings
- **Real-time Search**: Search through conversations with regex support
- **File Tree Browser**: Navigate your Claude conversations with a file tree view
- **Multiple Themes**: Choose between Matrix (green), Claude (purple), and Cyberpunk (neon) themes
- **Pure Keyboard Navigation**: Vim-style keybindings for efficient navigation
- **High Performance**: Built in Rust for sub-second response times
- **Zero Dependencies**: Standalone binary that works without Python

## Building

### Standalone Binary

```bash
cd rust_tui
cargo build --release
```

The binary will be available at `target/release/claude-tui`

### Python Integration (Optional)

If you want to use the TUI from Python:

```bash
# Install maturin
pipx install maturin

# Build Python wheel
maturin build --features python

# Install in development mode
maturin develop --features python
```

## Usage

### Standalone

```bash
./target/release/claude-tui
```

### From Python Package

After building the project, you can launch the TUI from the main interactive UI:

1. Run the main extractor: `python3 interactive_ui.py`
2. Select option `N` to launch the new high-performance Rust TUI

## Keyboard Shortcuts

### Global
- `1-6`: Switch between pages
- `q`: Quit application
- `?`: Show help
- `t`: Toggle theme

### Navigation
- `j`/`↓`: Move down
- `k`/`↑`: Move up
- `h`/`←`: Move left/collapse
- `l`/`→`: Move right/expand
- `Enter`: Select/open
- `Space`: Toggle selection
- `Tab`: Next field
- `Shift+Tab`: Previous field

### Search Page
- `/`: Start search
- `Ctrl+R`: Toggle regex mode
- `Ctrl+L`: Clear search
- `Enter`: Execute search

### Export Page
- `e`: Export selected
- `a`: Select all
- `n`: Select none
- `i`: Invert selection

## Themes

The TUI includes three built-in themes:

1. **Matrix**: Classic green-on-black terminal aesthetic
2. **Claude**: Purple and orange, matching Claude's branding
3. **Cyberpunk**: Neon colors with a futuristic feel

Toggle between themes with the `t` key.

## Performance

The Rust TUI is optimized for performance:

- **Instant startup**: < 100ms to launch
- **Real-time search**: Search through thousands of conversations instantly
- **Smooth scrolling**: 60+ FPS even with large file trees
- **Low memory usage**: < 50MB RAM for typical usage

## Architecture

The TUI is built with:

- **Ratatui**: Terminal UI framework
- **Tokio**: Async runtime for non-blocking operations
- **Crossterm**: Cross-platform terminal manipulation
- **PyO3**: Python bindings (optional)

The architecture follows a Redux-like pattern with:
- Centralized state management
- Action-based updates
- Effect system for side effects
- Virtual scrolling for large lists

## Development

### Project Structure

```
rust_tui/
├── src/
│   ├── app.rs           # Main application logic
│   ├── backend/         # Data access and processing
│   ├── config.rs        # Configuration management
│   ├── events.rs        # Event handling
│   ├── state.rs         # State management
│   ├── ui/              # User interface components
│   │   ├── pages/       # Individual pages
│   │   ├── theme.rs     # Theme definitions
│   │   └── widgets/     # Custom widgets
│   └── python_bindings.rs # Python integration (optional)
├── Cargo.toml           # Rust dependencies
└── pyproject.toml       # Python packaging config
```

### Building for Development

```bash
# Debug build (faster compilation)
cargo build

# Run with logging
RUST_LOG=debug ./target/debug/claude-tui

# Run tests
cargo test

# Check for issues
cargo clippy
```

## License

MIT License - See the main project's LICENSE file for details.
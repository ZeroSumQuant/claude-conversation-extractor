#!/usr/bin/env python3
"""Launch the Rust TUI for Claude Conversation Extractor."""

import os
import subprocess
import sys
from pathlib import Path

def launch_rust_tui():
    """Launch the high-performance Rust TUI."""
    # Find the TUI binary
    script_dir = Path(__file__).parent
    tui_binary = script_dir / "rust_tui" / "target" / "release" / "claude-tui"
    
    if not tui_binary.exists():
        # Try debug build
        tui_binary = script_dir / "rust_tui" / "target" / "debug" / "claude-tui"
    
    if not tui_binary.exists():
        print("Error: Rust TUI not built. Please run:")
        print("  cd rust_tui && cargo build --release")
        return 1
    
    # Launch the TUI
    try:
        return subprocess.call([str(tui_binary)] + sys.argv[1:])
    except KeyboardInterrupt:
        return 0
    except Exception as e:
        print(f"Error launching TUI: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(launch_rust_tui())
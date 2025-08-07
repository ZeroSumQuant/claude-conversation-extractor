#!/usr/bin/env python3
"""
Launcher script for Claude TUI

This script integrates with the existing Python CLI and provides
a seamless experience for users.
"""

import sys
import os
from pathlib import Path
from typing import Optional

# Try to import the Rust TUI
try:
    from claude_tui import launch_tui, RUST_TUI_AVAILABLE
except ImportError:
    RUST_TUI_AVAILABLE = False


def check_rust_tui_available() -> bool:
    """Check if the Rust TUI is available and compiled."""
    return RUST_TUI_AVAILABLE


def launch_rust_tui(config_path: Optional[str] = None) -> int:
    """Launch the Rust-based TUI."""
    if not RUST_TUI_AVAILABLE:
        print("Error: Rust TUI is not available.")
        print("Please build it with: cd rust_tui && maturin develop")
        return 1
    
    try:
        launch_tui(config_path)
        return 0
    except KeyboardInterrupt:
        print("\nTUI terminated by user.")
        return 0
    except Exception as e:
        print(f"Error launching TUI: {e}")
        return 1


def fallback_to_python_cli():
    """Fall back to the Python CLI if Rust TUI is not available."""
    # Import the existing Python CLI
    sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))
    
    try:
        from interactive_ui import InteractiveUI
        ui = InteractiveUI()
        ui.run()
    except ImportError:
        print("Error: Could not import Python CLI fallback.")
        print("Please ensure interactive_ui.py is in the project root.")
        sys.exit(1)


def main():
    """Main entry point that decides whether to use Rust TUI or Python CLI."""
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Claude Conversation Extractor TUI"
    )
    parser.add_argument(
        "--python",
        action="store_true",
        help="Force use of Python CLI instead of Rust TUI"
    )
    parser.add_argument(
        "--config",
        type=str,
        help="Path to configuration file"
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Check if Rust TUI is available and exit"
    )
    
    args = parser.parse_args()
    
    if args.check:
        if check_rust_tui_available():
            print("✓ Rust TUI is available")
            sys.exit(0)
        else:
            print("✗ Rust TUI is not available")
            print("Build with: cd rust_tui && maturin develop")
            sys.exit(1)
    
    if args.python or not check_rust_tui_available():
        print("Using Python CLI...")
        fallback_to_python_cli()
    else:
        print("Launching Rust TUI...")
        sys.exit(launch_rust_tui(args.config))


if __name__ == "__main__":
    main()
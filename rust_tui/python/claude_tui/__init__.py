"""Claude TUI - High-performance Terminal User Interface for Claude Conversation Extractor."""

try:
    from ._claude_tui import launch_tui, export_conversations, search_conversations
except ImportError as e:
    # Fallback for development or when Rust extension isn't built
    def launch_tui(*args, **kwargs):
        raise ImportError(
            "Rust TUI extension not built. Run 'maturin develop' to build it."
        ) from e
    
    def export_conversations(*args, **kwargs):
        raise ImportError(
            "Rust TUI extension not built. Run 'maturin develop' to build it."
        ) from e
    
    def search_conversations(*args, **kwargs):
        raise ImportError(
            "Rust TUI extension not built. Run 'maturin develop' to build it."
        ) from e

__version__ = "0.1.0"
__all__ = ["launch_tui", "export_conversations", "search_conversations"]

def main():
    """Main entry point for the TUI."""
    import sys
    launch_tui(sys.argv[1:] if len(sys.argv) > 1 else [])

if __name__ == "__main__":
    main()
#!/usr/bin/env python3
"""
Integration module for Claude TUI

This module provides seamless integration between the existing Python CLI
and the new Rust-based TUI.
"""

import sys
import os
from pathlib import Path
from typing import Optional, List, Dict, Any

# Try to import the Rust TUI
RUST_TUI_AVAILABLE = False
try:
    # Add rust_tui to path
    rust_tui_path = Path(__file__).parent / "rust_tui" / "python"
    sys.path.insert(0, str(rust_tui_path))
    
    from claude_tui import (
        launch_tui,
        search_conversations as rust_search,
        export_conversations as rust_export,
        get_stats as rust_stats,
        RUST_TUI_AVAILABLE as _TUI_AVAILABLE
    )
    RUST_TUI_AVAILABLE = _TUI_AVAILABLE
except ImportError:
    pass


class ClaudeTUIIntegration:
    """Integration class for Claude TUI"""
    
    def __init__(self):
        self.rust_available = RUST_TUI_AVAILABLE
        self.prefer_rust = True  # Prefer Rust TUI if available
    
    def launch(self, force_python: bool = False) -> int:
        """
        Launch the appropriate UI based on availability and preferences.
        
        Args:
            force_python: Force use of Python CLI even if Rust TUI is available
            
        Returns:
            Exit code (0 for success, non-zero for error)
        """
        if not force_python and self.rust_available and self.prefer_rust:
            return self._launch_rust_tui()
        else:
            return self._launch_python_cli()
    
    def _launch_rust_tui(self) -> int:
        """Launch the Rust TUI"""
        try:
            print("Launching high-performance Rust TUI...")
            launch_tui()
            return 0
        except KeyboardInterrupt:
            print("\nTUI terminated by user.")
            return 0
        except Exception as e:
            print(f"Error launching Rust TUI: {e}")
            print("Falling back to Python CLI...")
            return self._launch_python_cli()
    
    def _launch_python_cli(self) -> int:
        """Launch the Python CLI"""
        try:
            from interactive_ui import InteractiveUI
            print("Launching Python CLI...")
            ui = InteractiveUI()
            ui.run()
            return 0
        except KeyboardInterrupt:
            print("\nCLI terminated by user.")
            return 0
        except Exception as e:
            print(f"Error launching Python CLI: {e}")
            return 1
    
    def search(self, query: str, use_regex: bool = False) -> List[Dict[str, Any]]:
        """
        Search conversations using the best available engine.
        
        Args:
            query: Search query
            use_regex: Use regex matching
            
        Returns:
            List of search results
        """
        if self.rust_available:
            try:
                results = rust_search(query, use_regex)
                return [
                    {
                        "id": r.conversation_id,
                        "title": r.title,
                        "project": r.project,
                        "score": r.score,
                        "match_count": r.match_count,
                    }
                    for r in results
                ]
            except Exception as e:
                print(f"Rust search failed: {e}, falling back to Python")
        
        # Fall back to Python search
        from search_conversations import search_conversations_content
        results = search_conversations_content(query, use_regex=use_regex)
        return results
    
    def export(
        self,
        conversation_ids: List[str],
        format: str = "markdown",
        output_path: str = None
    ) -> bool:
        """
        Export conversations using the best available exporter.
        
        Args:
            conversation_ids: List of conversation IDs to export
            format: Export format (markdown, json, html, pdf, zip)
            output_path: Output file path
            
        Returns:
            True if successful, False otherwise
        """
        if output_path is None:
            output_path = f"export.{format}"
        
        if self.rust_available:
            try:
                rust_export(conversation_ids, format, output_path)
                print(f"Exported {len(conversation_ids)} conversations to {output_path}")
                return True
            except Exception as e:
                print(f"Rust export failed: {e}, falling back to Python")
        
        # Fall back to Python export
        from export_formats import export_to_format
        try:
            export_to_format(conversation_ids, format, output_path)
            print(f"Exported {len(conversation_ids)} conversations to {output_path}")
            return True
        except Exception as e:
            print(f"Export failed: {e}")
            return False
    
    def get_stats(self) -> Dict[str, Any]:
        """
        Get conversation statistics using the best available method.
        
        Returns:
            Dictionary with statistics
        """
        if self.rust_available:
            try:
                stats = rust_stats()
                return {
                    "total_conversations": stats.total_conversations,
                    "total_size_bytes": stats.total_size_bytes,
                    "size_mb": stats.size_mb,
                }
            except Exception as e:
                print(f"Rust stats failed: {e}, falling back to Python")
        
        # Fall back to Python stats
        from conversation_stats import calculate_stats
        return calculate_stats()
    
    def check_rust_available(self) -> bool:
        """Check if Rust TUI is available"""
        return self.rust_available
    
    def build_rust_tui(self) -> bool:
        """
        Attempt to build the Rust TUI.
        
        Returns:
            True if build successful, False otherwise
        """
        import subprocess
        
        rust_tui_dir = Path(__file__).parent / "rust_tui"
        if not rust_tui_dir.exists():
            print(f"Rust TUI directory not found: {rust_tui_dir}")
            return False
        
        try:
            print("Building Rust TUI...")
            result = subprocess.run(
                ["./build.sh"],
                cwd=rust_tui_dir,
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                print("Rust TUI built successfully!")
                # Reload to check if it's now available
                self.__init__()
                return True
            else:
                print(f"Build failed: {result.stderr}")
                return False
        except Exception as e:
            print(f"Build error: {e}")
            return False


def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Claude Conversation Extractor - Enhanced TUI"
    )
    parser.add_argument(
        "--python",
        action="store_true",
        help="Force use of Python CLI"
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Check if Rust TUI is available"
    )
    parser.add_argument(
        "--build",
        action="store_true",
        help="Build the Rust TUI"
    )
    parser.add_argument(
        "--stats",
        action="store_true",
        help="Show conversation statistics"
    )
    
    args = parser.parse_args()
    
    integration = ClaudeTUIIntegration()
    
    if args.check:
        if integration.check_rust_available():
            print("✓ Rust TUI is available")
        else:
            print("✗ Rust TUI is not available")
            print("Build with: python claude_tui_integration.py --build")
        sys.exit(0)
    
    if args.build:
        if integration.build_rust_tui():
            sys.exit(0)
        else:
            sys.exit(1)
    
    if args.stats:
        stats = integration.get_stats()
        print(f"Total conversations: {stats.get('total_conversations', 0)}")
        print(f"Total size: {stats.get('size_mb', 0):.2f} MB")
        sys.exit(0)
    
    # Launch the UI
    sys.exit(integration.launch(force_python=args.python))


if __name__ == "__main__":
    main()
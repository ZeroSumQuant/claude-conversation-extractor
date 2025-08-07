#!/usr/bin/env python3
"""
Export format handlers for Claude Conversation Extractor.

Supports multiple export formats:
- Markdown (default)
- JSON (structured data)
- HTML (web viewable with syntax highlighting)
"""

import json
import html
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any

# HTML template constants
HTML_STYLE = """
<style>
    body {
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        max-width: 900px;
        margin: 0 auto;
        padding: 20px;
        background: #f5f5f5;
        color: #333;
    }
    .container {
        background: white;
        border-radius: 8px;
        padding: 30px;
        box-shadow: 0 2px 10px rgba(0,0,0,0.1);
    }
    h1 {
        color: #2c3e50;
        border-bottom: 3px solid #3498db;
        padding-bottom: 10px;
    }
    .metadata {
        color: #666;
        font-size: 0.9em;
        margin-bottom: 30px;
        padding: 10px;
        background: #f8f9fa;
        border-radius: 4px;
    }
    .message {
        margin: 20px 0;
        padding: 15px;
        border-radius: 8px;
        border-left: 4px solid;
    }
    .user-message {
        background: #e3f2fd;
        border-color: #2196F3;
    }
    .assistant-message {
        background: #f3e5f5;
        border-color: #9c27b0;
    }
    .tool-call {
        background: #fff3e0;
        border-color: #ff9800;
        font-family: 'Courier New', monospace;
        font-size: 0.9em;
    }
    .tool-result {
        background: #e8f5e9;
        border-color: #4caf50;
        font-family: 'Courier New', monospace;
        font-size: 0.9em;
    }
    .message-header {
        font-weight: bold;
        margin-bottom: 10px;
        display: flex;
        align-items: center;
        gap: 10px;
    }
    .timestamp {
        font-size: 0.85em;
        color: #666;
        font-weight: normal;
    }
    .content {
        white-space: pre-wrap;
        word-wrap: break-word;
    }
    .code-block {
        background: #282c34;
        color: #abb2bf;
        padding: 15px;
        border-radius: 4px;
        overflow-x: auto;
        font-family: 'Courier New', monospace;
        font-size: 0.9em;
        margin: 10px 0;
    }
    .icon {
        font-size: 1.2em;
    }
    hr {
        border: none;
        border-top: 1px solid #e0e0e0;
        margin: 30px 0;
    }
</style>
"""


class ExportFormatter:
    """Base class for export format handlers"""
    
    def __init__(self, output_dir: Path):
        """
        Initialize the formatter.
        
        Args:
            output_dir: Directory to save exported files
        """
        self.output_dir = output_dir
        self.output_dir.mkdir(parents=True, exist_ok=True)
    
    def export(self, conversation: List[Dict[str, Any]], session_id: str, 
               metadata: Optional[Dict[str, Any]] = None) -> Path:
        """
        Export conversation in the specific format.
        
        Args:
            conversation: List of message dictionaries
            session_id: Unique session identifier
            metadata: Optional metadata about the conversation
            
        Returns:
            Path to the exported file
        """
        raise NotImplementedError("Subclasses must implement export()")


class MarkdownExporter(ExportFormatter):
    """Export conversations to Markdown format"""
    
    def export(self, conversation: List[Dict[str, Any]], session_id: str,
               metadata: Optional[Dict[str, Any]] = None) -> Path:
        """Export to Markdown format"""
        # Generate filename
        date_str = datetime.now().strftime("%Y-%m-%d")
        filename = f"claude-conversation-{date_str}-{session_id[:8]}.md"
        output_path = self.output_dir / filename
        
        with open(output_path, "w", encoding="utf-8") as f:
            # Write header
            f.write("# Claude Conversation Log\n\n")
            
            # Write metadata if provided
            if metadata:
                f.write(f"**Session ID:** {session_id}\n")
                if "date" in metadata:
                    f.write(f"**Date:** {metadata['date']}\n")
                if "message_count" in metadata:
                    f.write(f"**Messages:** {metadata['message_count']}\n")
                if "project" in metadata:
                    f.write(f"**Project:** {metadata['project']}\n")
                f.write("\n---\n\n")
            else:
                f.write(f"Session ID: {session_id}\n")
                f.write(f"Date: {date_str}\n\n---\n\n")
            
            # Write messages
            for msg in conversation:
                role = msg.get("role", "unknown")
                content = msg.get("content", "")
                timestamp = msg.get("timestamp", "")
                
                if role == "user":
                    f.write("## 👤 User")
                elif role == "assistant":
                    f.write("## 🤖 Claude")
                else:
                    f.write(f"## {role.title()}")
                
                if timestamp:
                    f.write(f" *[{timestamp}]*")
                f.write("\n\n")
                
                f.write(f"{content}\n\n")
                f.write("---\n\n")
        
        return output_path


class JSONExporter(ExportFormatter):
    """Export conversations to JSON format"""
    
    def export(self, conversation: List[Dict[str, Any]], session_id: str,
               metadata: Optional[Dict[str, Any]] = None) -> Path:
        """Export to JSON format"""
        # Generate filename
        date_str = datetime.now().strftime("%Y-%m-%d")
        filename = f"claude-conversation-{date_str}-{session_id[:8]}.json"
        output_path = self.output_dir / filename
        
        # Build JSON structure
        export_data = {
            "session_id": session_id,
            "export_date": datetime.now().isoformat(),
            "metadata": metadata or {},
            "conversation": conversation
        }
        
        # Add statistics
        export_data["statistics"] = {
            "total_messages": len(conversation),
            "user_messages": sum(1 for msg in conversation if msg.get("role") == "user"),
            "assistant_messages": sum(1 for msg in conversation if msg.get("role") == "assistant"),
        }
        
        # Write JSON file
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(export_data, f, indent=2, ensure_ascii=False, default=str)
        
        return output_path


class HTMLExporter(ExportFormatter):
    """Export conversations to HTML format with styling"""
    
    def export(self, conversation: List[Dict[str, Any]], session_id: str,
               metadata: Optional[Dict[str, Any]] = None) -> Path:
        """Export to HTML format with rich formatting"""
        # Generate filename
        date_str = datetime.now().strftime("%Y-%m-%d")
        filename = f"claude-conversation-{date_str}-{session_id[:8]}.html"
        output_path = self.output_dir / filename
        
        with open(output_path, "w", encoding="utf-8") as f:
            # Write HTML header
            f.write("""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Claude Conversation - {}</title>
    {}
</head>
<body>
    <div class="container">
""".format(session_id[:8], HTML_STYLE))
            
            # Write title and metadata
            f.write("<h1>Claude Conversation Log</h1>\n")
            f.write('<div class="metadata">\n')
            f.write(f"<strong>Session ID:</strong> {session_id}<br>\n")
            
            if metadata:
                if "date" in metadata:
                    f.write(f"<strong>Date:</strong> {metadata['date']}<br>\n")
                if "message_count" in metadata:
                    f.write(f"<strong>Total Messages:</strong> {metadata['message_count']}<br>\n")
                if "project" in metadata:
                    f.write(f"<strong>Project:</strong> {html.escape(metadata['project'])}<br>\n")
            else:
                f.write(f"<strong>Export Date:</strong> {date_str}<br>\n")
            
            f.write("</div>\n\n")
            
            # Write messages
            for msg in conversation:
                role = msg.get("role", "unknown")
                content = msg.get("content", "")
                timestamp = msg.get("timestamp", "")
                msg_type = msg.get("type", role)
                
                # Determine CSS class and icon
                if role == "user":
                    css_class = "user-message"
                    icon = "👤"
                    title = "User"
                elif role == "assistant":
                    css_class = "assistant-message"
                    icon = "🤖"
                    title = "Claude"
                elif msg_type == "tool_call":
                    css_class = "tool-call"
                    icon = "🔧"
                    title = "Tool Call"
                elif msg_type == "tool_result":
                    css_class = "tool-result"
                    icon = "📤"
                    title = "Tool Result"
                else:
                    css_class = "message"
                    icon = "💬"
                    title = role.title()
                
                f.write(f'<div class="message {css_class}">\n')
                f.write(f'<div class="message-header">\n')
                f.write(f'<span class="icon">{icon}</span>\n')
                f.write(f'<span>{title}</span>\n')
                
                if timestamp:
                    f.write(f'<span class="timestamp">{timestamp}</span>\n')
                
                f.write('</div>\n')
                
                # Process content - escape HTML and handle code blocks
                content_html = self._process_content_for_html(content)
                f.write(f'<div class="content">{content_html}</div>\n')
                f.write('</div>\n\n')
            
            # Write footer
            f.write("""
    </div>
    <script>
        // Add copy functionality for code blocks
        document.querySelectorAll('.code-block').forEach(block => {
            block.style.cursor = 'pointer';
            block.title = 'Click to copy';
            block.addEventListener('click', () => {
                navigator.clipboard.writeText(block.textContent);
                const original = block.style.background;
                block.style.background = '#4caf50';
                setTimeout(() => block.style.background = original, 200);
            });
        });
    </script>
</body>
</html>
""")
        
        return output_path
    
    def _process_content_for_html(self, content: str) -> str:
        """Process content for HTML display with code block detection"""
        if not content:
            return ""
        
        # Escape HTML
        content = html.escape(content)
        
        # Detect and format code blocks (simple approach)
        lines = content.split('\n')
        in_code_block = False
        processed_lines = []
        
        for line in lines:
            if line.strip().startswith('```'):
                if in_code_block:
                    processed_lines.append('</div>')
                    in_code_block = False
                else:
                    processed_lines.append('<div class="code-block">')
                    in_code_block = True
            else:
                processed_lines.append(line)
        
        # Close any unclosed code block
        if in_code_block:
            processed_lines.append('</div>')
        
        return '\n'.join(processed_lines)


class ExportManager:
    """Manager for handling multiple export formats"""
    
    def __init__(self, output_dir: Path):
        """
        Initialize the export manager.
        
        Args:
            output_dir: Base directory for exports
        """
        self.output_dir = output_dir
        self.exporters = {
            "markdown": MarkdownExporter(output_dir),
            "md": MarkdownExporter(output_dir),
            "json": JSONExporter(output_dir),
            "html": HTMLExporter(output_dir),
        }
    
    def export(self, conversation: List[Dict[str, Any]], session_id: str,
               format: str = "markdown", metadata: Optional[Dict[str, Any]] = None) -> Path:
        """
        Export conversation in the specified format.
        
        Args:
            conversation: List of message dictionaries
            session_id: Unique session identifier
            format: Export format (markdown, json, html)
            metadata: Optional metadata about the conversation
            
        Returns:
            Path to the exported file
            
        Raises:
            ValueError: If format is not supported
        """
        format_lower = format.lower()
        
        if format_lower not in self.exporters:
            available = ", ".join(self.exporters.keys())
            raise ValueError(f"Unsupported format: {format}. Available: {available}")
        
        exporter = self.exporters[format_lower]
        return exporter.export(conversation, session_id, metadata)
    
    def export_multiple_formats(self, conversation: List[Dict[str, Any]], 
                                session_id: str, formats: List[str],
                                metadata: Optional[Dict[str, Any]] = None) -> List[Path]:
        """
        Export conversation in multiple formats.
        
        Args:
            conversation: List of message dictionaries
            session_id: Unique session identifier
            formats: List of export formats
            metadata: Optional metadata about the conversation
            
        Returns:
            List of paths to exported files
        """
        exported_paths = []
        
        for format in formats:
            try:
                path = self.export(conversation, session_id, format, metadata)
                exported_paths.append(path)
            except ValueError as e:
                print(f"Warning: {e}")
        
        return exported_paths


# Testing
if __name__ == "__main__":
    # Test the export formats
    test_conversation = [
        {
            "role": "user",
            "content": "Hello, Claude! Can you help me with Python?",
            "timestamp": "2024-01-15 10:30:00"
        },
        {
            "role": "assistant",
            "content": "Hello! I'd be happy to help you with Python. What would you like to know?",
            "timestamp": "2024-01-15 10:30:05"
        },
        {
            "role": "user",
            "content": "How do I read a JSON file?",
            "timestamp": "2024-01-15 10:30:15"
        },
        {
            "role": "assistant",
            "content": "Here's how to read a JSON file in Python:\n\n```python\nimport json\n\nwith open('data.json', 'r') as f:\n    data = json.load(f)\n```\n\nThis will load the JSON data into a Python dictionary.",
            "timestamp": "2024-01-15 10:30:20"
        }
    ]
    
    # Create export manager
    output_dir = Path("test_exports")
    manager = ExportManager(output_dir)
    
    # Test metadata
    metadata = {
        "date": "2024-01-15",
        "message_count": 4,
        "project": "Python Learning"
    }
    
    # Export in all formats
    formats = ["markdown", "json", "html"]
    paths = manager.export_multiple_formats(
        test_conversation, 
        "test123456", 
        formats,
        metadata
    )
    
    print(f"Exported {len(paths)} formats:")
    for path in paths:
        print(f"  - {path}")
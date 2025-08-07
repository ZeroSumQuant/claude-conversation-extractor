#!/usr/bin/env python3
"""
Detailed transcript export for Claude Conversation Extractor.

Exports full conversation transcripts including:
- Tool calls and their inputs
- Tool outputs (stdout/stderr)
- MCP responses
- File operations
- Command executions
"""

import json
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Union, Any

# Constants
MAX_CONTENT_DISPLAY = 2000
MAX_PREVIEW_LENGTH = 500
MAX_STDERR_DISPLAY = 1000
TRUNCATION_INDICATOR = "\n... (truncated)"


@dataclass
class ToolCall:
    """Represents a tool call in the conversation"""
    tool_name: str
    tool_id: str
    inputs: Dict[str, Any]
    timestamp: Optional[datetime] = None


@dataclass
class ToolResult:
    """Represents a tool result/response"""
    tool_use_id: str
    content: str
    is_error: bool
    stdout: Optional[str] = None
    stderr: Optional[str] = None
    is_image: bool = False
    timestamp: Optional[datetime] = None


class DetailedTranscriptExtractor:
    """Extract detailed transcripts including tool calls and responses"""
    
    def __init__(self, include_system_messages: bool = True):
        """
        Initialize the detailed extractor.
        
        Args:
            include_system_messages: Whether to include system/internal messages
        """
        self.include_system_messages = include_system_messages
    
    def extract_detailed_conversation(self, jsonl_path: Path) -> List[Dict[str, Any]]:
        """
        Extract detailed conversation including tool calls and results.
        
        Args:
            jsonl_path: Path to JSONL file
            
        Returns:
            List of detailed message dictionaries
        """
        detailed_messages = []
        
        try:
            with open(jsonl_path, "r", encoding="utf-8", errors="replace") as f:
                for line_num, line in enumerate(f, 1):
                    if not line.strip():
                        continue
                    
                    try:
                        entry = json.loads(line)
                        message = self._process_entry(entry)
                        if message:
                            detailed_messages.append(message)
                    except json.JSONDecodeError as e:
                        print(f"Warning: Invalid JSON at line {line_num}: {e}")
                    except Exception as e:
                        print(f"Warning: Error processing line {line_num}: {e}")
        
        except Exception as e:
            print(f"Error reading {jsonl_path}: {e}")
        
        return detailed_messages
    
    def _process_entry(self, entry: Dict) -> Optional[Dict[str, Any]]:
        """Process a single JSONL entry into a detailed message."""
        
        # Skip entries without type
        if "type" not in entry:
            return None
        
        entry_type = entry["type"]
        timestamp = entry.get("timestamp")
        
        # Parse timestamp if present
        if timestamp:
            try:
                timestamp = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
            except (ValueError, TypeError, AttributeError):
                timestamp = None
        
        # Handle user messages (including tool results)
        if entry_type == "user":
            return self._process_user_entry(entry, timestamp)
        
        # Handle assistant messages (including tool calls)
        elif entry_type == "assistant":
            return self._process_assistant_entry(entry, timestamp)
        
        # Handle system messages if requested
        elif self.include_system_messages and entry_type in ["system", "internal"]:
            return self._process_system_entry(entry, timestamp)
        
        return None
    
    def _process_user_entry(self, entry: Dict, timestamp: datetime) -> Dict[str, Any]:
        """Process user entries including tool results."""
        message_data = entry.get("message")
        
        # Handle cases where message is a string
        if isinstance(message_data, str):
            return {
                "type": "user",
                "content": message_data,
                "timestamp": timestamp
            }
        
        if not isinstance(message_data, dict):
            return {
                "type": "user",
                "content": str(message_data) if message_data else "",
                "timestamp": timestamp
            }
        
        content = message_data.get("content", "")
        
        # Check if this is a tool result
        if isinstance(content, list):
            for item in content:
                # Handle string items in list
                if isinstance(item, str):
                    continue
                if isinstance(item, dict) and item.get("type") == "tool_result":
                    # This is a tool result response
                    tool_result_data = entry.get("toolUseResult", {})
                    
                    return {
                        "type": "tool_result",
                        "tool_use_id": item.get("tool_use_id"),
                        "content": item.get("content", ""),
                        "is_error": item.get("is_error", False),
                        "stdout": tool_result_data.get("stdout"),
                        "stderr": tool_result_data.get("stderr"),
                        "is_image": tool_result_data.get("isImage", False),
                        "interrupted": tool_result_data.get("interrupted", False),
                        "timestamp": timestamp
                    }
                elif isinstance(item, dict) and item.get("type") == "text":
                    content = item.get("text", "")
                elif isinstance(item, str):
                    content = item
        
        # Regular user message
        return {
            "type": "user",
            "content": self._extract_text_content(content),
            "timestamp": timestamp
        }
    
    def _process_assistant_entry(self, entry: Dict, timestamp: datetime) -> Dict[str, Any]:
        """Process assistant entries including tool calls."""
        message_data = entry.get("message")
        
        # Handle cases where message is a string
        if isinstance(message_data, str):
            return {
                "type": "assistant",
                "content": message_data,
                "timestamp": timestamp
            }
        
        if not isinstance(message_data, dict):
            return {
                "type": "assistant",
                "content": str(message_data) if message_data else "",
                "timestamp": timestamp
            }
        
        content = message_data.get("content", "")
        
        # Check if this contains tool calls
        tool_calls = []
        text_content = ""
        
        if isinstance(content, list):
            for item in content:
                if isinstance(item, dict):
                    if item.get("type") == "tool_use":
                        # Extract tool call details
                        tool_calls.append({
                            "tool_name": item.get("name"),
                            "tool_id": item.get("id"),
                            "inputs": item.get("input", {})
                        })
                    elif item.get("type") == "text":
                        text_content += item.get("text", "")
                elif isinstance(item, str):
                    text_content += item
        elif isinstance(content, str):
            text_content = content
        
        # Build response based on content
        if tool_calls:
            return {
                "type": "tool_calls",
                "tools": tool_calls,
                "text": text_content,
                "timestamp": timestamp,
                "model": message_data.get("model")
            }
        else:
            return {
                "type": "assistant",
                "content": text_content or self._extract_text_content(content),
                "timestamp": timestamp,
                "model": message_data.get("model")
            }
    
    def _process_system_entry(self, entry: Dict, timestamp: datetime) -> Dict[str, Any]:
        """Process system/internal messages."""
        return {
            "type": "system",
            "content": str(entry.get("message", entry)),
            "timestamp": timestamp
        }
    
    def _extract_text_content(self, content: Any) -> str:
        """Extract text from various content formats."""
        if isinstance(content, str):
            return content
        elif isinstance(content, list):
            text_parts = []
            for item in content:
                if isinstance(item, dict):
                    if item.get("type") == "text":
                        text_parts.append(item.get("text", ""))
                elif isinstance(item, str):
                    text_parts.append(item)
            return "\n".join(text_parts)
        elif isinstance(content, dict):
            return str(content)
        else:
            return str(content)
    
    def save_detailed_markdown(
        self, 
        messages: List[Dict[str, Any]], 
        output_path: Path,
        include_raw_json: bool = False
    ) -> Path:
        """
        Save detailed conversation to markdown with tool calls highlighted.
        
        Args:
            messages: List of detailed messages
            output_path: Path for output file
            include_raw_json: Whether to include raw JSON for tool calls
            
        Returns:
            Path to saved file
        """
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        with open(output_path, "w", encoding="utf-8") as f:
            f.write("# Claude Conversation - Detailed Transcript\n\n")
            f.write(f"*Exported: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}*\n\n")
            f.write("---\n\n")
            
            for msg in messages:
                msg_type = msg.get("type")
                timestamp = msg.get("timestamp")
                
                # Format timestamp
                time_str = ""
                if timestamp:
                    time_str = f" *[{timestamp.strftime('%H:%M:%S')}]*"
                
                if msg_type == "user":
                    f.write(f"## 👤 Human{time_str}\n\n")
                    f.write(f"{msg.get('content', '')}\n\n")
                
                elif msg_type == "assistant":
                    model = msg.get("model", "Claude")
                    f.write(f"## 🤖 {model}{time_str}\n\n")
                    f.write(f"{msg.get('content', '')}\n\n")
                
                elif msg_type == "tool_calls":
                    model = msg.get("model", "Claude")
                    f.write(f"## 🤖 {model}{time_str}\n\n")
                    
                    # Add any text content
                    if msg.get("text"):
                        f.write(f"{msg['text']}\n\n")
                    
                    # Format tool calls
                    for tool in msg.get("tools", []):
                        f.write("### 🔧 Tool Call\n\n")
                        f.write(f"**Tool:** `{tool['tool_name']}`\n")
                        f.write(f"**ID:** `{tool['tool_id']}`\n\n")
                        
                        # Format inputs based on tool type
                        inputs = tool.get("inputs", {})
                        if tool["tool_name"] == "Bash":
                            f.write("**Command:**\n```bash\n")
                            f.write(f"{inputs.get('command', '')}\n")
                            f.write("```\n")
                            if inputs.get("description"):
                                f.write(f"*{inputs['description']}*\n")
                        elif tool["tool_name"] in ["Read", "Write", "Edit"]:
                            file_path = inputs.get('file_path', '')
                            if isinstance(file_path, list):
                                file_path = str(file_path)
                            f.write(f"**File:** `{file_path}`\n")
                            if tool["tool_name"] == "Write" and inputs.get("content"):
                                f.write("\n**Content:**\n```\n")
                                f.write(f"{inputs['content'][:MAX_PREVIEW_LENGTH]}")
                                if len(inputs['content']) > MAX_PREVIEW_LENGTH:
                                    f.write(TRUNCATION_INDICATOR)
                                f.write("\n```\n")
                        elif include_raw_json:
                            f.write("\n**Inputs:**\n```json\n")
                            f.write(json.dumps(inputs, indent=2)[:MAX_STDERR_DISPLAY])
                            if len(json.dumps(inputs)) > MAX_STDERR_DISPLAY:
                                f.write(TRUNCATION_INDICATOR)
                            f.write("\n```\n")
                        
                        f.write("\n")
                
                elif msg_type == "tool_result":
                    f.write(f"### 📤 Tool Result{time_str}\n\n")
                    
                    if msg.get("is_error"):
                        f.write("**❌ ERROR**\n\n")
                    
                    # Show stdout if present
                    if msg.get("stdout"):
                        f.write("**Output:**\n```\n")
                        stdout = msg["stdout"]
                        if len(stdout) > MAX_CONTENT_DISPLAY:
                            f.write(stdout[:MAX_CONTENT_DISPLAY])
                            f.write(TRUNCATION_INDICATOR)
                        else:
                            f.write(stdout)
                        f.write("\n```\n\n")
                    
                    # Show stderr if present
                    if msg.get("stderr"):
                        f.write("**Errors:**\n```\n")
                        f.write(msg["stderr"][:MAX_STDERR_DISPLAY])
                        if len(msg["stderr"]) > MAX_STDERR_DISPLAY:
                            f.write(TRUNCATION_INDICATOR)
                        f.write("\n```\n\n")
                    
                    # Show content if no stdout/stderr
                    if not msg.get("stdout") and not msg.get("stderr"):
                        content = msg.get("content", "")
                        # Ensure content is a string
                        if isinstance(content, list):
                            content = str(content)
                        elif not isinstance(content, str):
                            content = str(content)
                        
                        if content:
                            f.write("**Result:**\n```\n")
                            if len(content) > MAX_CONTENT_DISPLAY:
                                f.write(content[:MAX_CONTENT_DISPLAY])
                                f.write(TRUNCATION_INDICATOR)
                            else:
                                f.write(content)
                            f.write("\n```\n\n")
                
                elif msg_type == "system" and self.include_system_messages:
                    f.write(f"### ⚙️ System{time_str}\n\n")
                    f.write(f"```\n{msg.get('content', '')[:MAX_PREVIEW_LENGTH]}\n```\n\n")
                
                f.write("---\n\n")
        
        return output_path


# Testing
if __name__ == "__main__":
    import sys
    
    if len(sys.argv) > 1:
        jsonl_file = Path(sys.argv[1])
        if jsonl_file.exists():
            extractor = DetailedTranscriptExtractor(include_system_messages=False)
            messages = extractor.extract_detailed_conversation(jsonl_file)
            
            print(f"Extracted {len(messages)} detailed messages")
            
            # Save to file
            output_path = Path("detailed_transcript.md")
            extractor.save_detailed_markdown(messages, output_path, include_raw_json=True)
            print(f"Saved to {output_path}")
        else:
            print(f"File not found: {jsonl_file}")
    else:
        print("Usage: python detailed_export.py <jsonl_file>")
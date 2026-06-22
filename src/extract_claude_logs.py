#!/usr/bin/env python3
"""
Extract clean conversation logs from Claude Code's internal JSONL files

This tool parses the undocumented JSONL format used by Claude Code to store
conversations locally in ~/.claude/projects/ and exports them as clean,
readable markdown files.
"""

import argparse
import json
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

try:
    from .source_config import get_source_config, normalize_source
except ImportError:
    from source_config import get_source_config, normalize_source


class ClaudeConversationExtractor:
    """Extract and convert Claude Code conversations from JSONL to markdown."""

    def __init__(self, output_dir: Optional[Path] = None, source: str = "claude"):
        """Initialize the extractor with source directory and output location."""
        self.source = normalize_source(source)
        self.source_config = get_source_config(self.source)
        self.claude_dir = self.source_config["session_dir"]
        self.session_dir = self.claude_dir

        if output_dir:
            self.output_dir = Path(output_dir)
            self.output_dir.mkdir(parents=True, exist_ok=True)
        else:
            possible_dirs = self.source_config["default_output_dirs"] + [
                self.source_config["default_output_fallback"]
            ]

            # Use the first directory we can create
            for dir_path in possible_dirs:
                try:
                    dir_path.mkdir(parents=True, exist_ok=True)
                    # Test if we can write to it
                    test_file = dir_path / ".test"
                    test_file.touch()
                    test_file.unlink()
                    self.output_dir = dir_path
                    break
                except Exception:
                    continue
            else:
                self.output_dir = self.source_config["default_output_fallback"]
                self.output_dir.mkdir(exist_ok=True)

        print(f"📁 Saving logs to: {self.output_dir}")

    def find_sessions(self, project_path: Optional[str] = None) -> List[Path]:
        """Find all JSONL session files, sorted by most recent first."""
        if project_path:
            search_dir = self.session_dir / project_path
        else:
            search_dir = self.session_dir

        sessions = []
        if search_dir.exists():
            for session_file in search_dir.rglob(self.source_config["session_glob"]):
                sessions.append(session_file)
        return sorted(sessions, key=lambda x: x.stat().st_mtime, reverse=True)

    def extract_conversation(self, jsonl_path: Path, detailed: bool = False, thinking: bool = False) -> List[Dict[str, str]]:
        """Extract conversation messages from a JSONL file.

        Args:
            jsonl_path: Path to the JSONL file
            detailed: If True, include tool use, MCP responses, and system messages
            thinking: If True, include extended thinking blocks
        """
        if self.source == "copilot":
            return self._extract_copilot_conversation(
                jsonl_path, detailed=detailed, thinking=thinking
            )
        return self._extract_claude_conversation(
            jsonl_path, detailed=detailed, thinking=thinking
        )

    def _extract_claude_conversation(
        self, jsonl_path: Path, detailed: bool = False, thinking: bool = False
    ) -> List[Dict[str, str]]:
        conversation = []

        try:
            with open(jsonl_path, "r", encoding="utf-8") as f:
                for line in f:
                    try:
                        entry = json.loads(line.strip())

                        if entry.get("type") == "user" and "message" in entry:
                            msg = entry["message"]
                            if isinstance(msg, dict) and msg.get("role") == "user":
                                text = self._extract_text_content(msg.get("content", ""))
                                self._append_message(conversation, "user", text, entry.get("timestamp", ""))

                        elif entry.get("type") == "assistant" and "message" in entry:
                            msg = entry["message"]
                            if isinstance(msg, dict) and msg.get("role") == "assistant":
                                text = self._extract_text_content(
                                    msg.get("content", []), detailed=detailed, thinking=thinking
                                )
                                self._append_message(
                                    conversation, "assistant", text, entry.get("timestamp", "")
                                )

                        elif detailed:
                            if entry.get("type") == "tool_use":
                                tool_data = entry.get("tool", {})
                                self._append_message(
                                    conversation,
                                    "tool_use",
                                    f"🔧 Tool: {tool_data.get('name', 'unknown')}\n"
                                    f"Input: {json.dumps(tool_data.get('input', {}), indent=2)}",
                                    entry.get("timestamp", ""),
                                )
                            elif entry.get("type") == "tool_result":
                                result = entry.get("result", {})
                                output = result.get("output", "") or result.get("error", "")
                                self._append_message(
                                    conversation,
                                    "tool_result",
                                    f"📤 Result:\n{output}",
                                    entry.get("timestamp", ""),
                                )
                            elif entry.get("type") == "system" and "message" in entry:
                                self._append_message(
                                    conversation,
                                    "system",
                                    f"ℹ️ System: {entry.get('message', '')}",
                                    entry.get("timestamp", ""),
                                )

                    except json.JSONDecodeError:
                        continue
                    except Exception:
                        continue

        except Exception as e:
            print(f"❌ Error reading file {jsonl_path}: {e}")

        return conversation

    def _extract_copilot_conversation(
        self, jsonl_path: Path, detailed: bool = False, thinking: bool = False
    ) -> List[Dict[str, str]]:
        conversation = []

        try:
            with open(jsonl_path, "r", encoding="utf-8") as f:
                for line in f:
                    try:
                        entry = json.loads(line.strip())
                        event_type = entry.get("type", "")
                        data = entry.get("data", {})
                        timestamp = entry.get("timestamp", "")

                        if event_type == "user.message":
                            text = self._extract_copilot_text_content(
                                data.get("content", "") or data.get("transformedContent", "")
                            )
                            self._append_message(conversation, "user", text, timestamp)

                        elif event_type == "assistant.message":
                            text = self._extract_copilot_text_content(data.get("content", ""))
                            if thinking and data.get("reasoningText"):
                                text = f"{text}\n\n💭 Thinking:\n{data.get('reasoningText')}"
                            self._append_message(conversation, "assistant", text, timestamp)

                        elif detailed and event_type == "tool.execution_start":
                            self._append_message(
                                conversation,
                                "tool_use",
                                f"🔧 Tool: {data.get('toolName', 'unknown')}\n"
                                f"Input: {self._stringify_value(data.get('arguments', {}))}",
                                timestamp,
                            )

                        elif detailed and event_type == "tool.execution_complete":
                            result_prefix = "📤 Result" if data.get("success") else "❌ Error"
                            payload = data.get("result") if data.get("success") else data.get("error")
                            self._append_message(
                                conversation,
                                "tool_result",
                                f"{result_prefix}:\n{self._stringify_value(payload)}",
                                timestamp,
                            )

                        elif detailed and event_type in {
                            "session.info",
                            "session.warning",
                            "session.resume",
                            "session.shutdown",
                            "system.notification",
                            "abort",
                            "subagent.started",
                        }:
                            summary = data.get("message") or self._stringify_value(data)
                            self._append_message(
                                conversation,
                                "system",
                                f"ℹ️ {event_type}: {summary}",
                                timestamp,
                            )

                    except json.JSONDecodeError:
                        continue
                    except Exception:
                        continue

        except Exception as e:
            print(f"❌ Error reading file {jsonl_path}: {e}")

        return conversation

    def _append_message(
        self, conversation: List[Dict[str, str]], role: str, content: str, timestamp: str
    ) -> None:
        if content and content.strip():
            conversation.append(
                {
                    "role": role,
                    "content": content,
                    "timestamp": timestamp,
                }
            )

    def _extract_copilot_text_content(self, content: Any) -> str:
        """Extract text from Copilot event payloads."""
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            return "\n".join(self._extract_copilot_text_content(item) for item in content if item)
        if isinstance(content, dict):
            if isinstance(content.get("text"), str):
                return content["text"]
            return self._stringify_value(content)
        return str(content)

    def _stringify_value(self, value: Any) -> str:
        """Format structured values for readable export."""
        if value is None:
            return ""
        if isinstance(value, (dict, list)):
            return json.dumps(value, indent=2, ensure_ascii=False)
        return str(value)

    def _get_session_id(self, session_path: Path) -> str:
        """Return a stable session identifier for the active source."""
        if self.source == "copilot" and session_path.name == "events.jsonl":
            return session_path.parent.name
        return session_path.stem

    def _get_session_display_name(self, session_path: Path) -> str:
        """Return the best available project/workspace label for a session."""
        if self.source == "copilot":
            try:
                with open(session_path, "r", encoding="utf-8") as f:
                    for line in f:
                        entry = json.loads(line.strip())
                        if entry.get("type") == "session.start":
                            context = entry.get("data", {}).get("context", {})
                            cwd = context.get("cwd")
                            if cwd:
                                return Path(cwd).name or cwd
                        if entry.get("type") == "user.message":
                            break
            except Exception:
                pass
            return session_path.parent.name

        project = session_path.parent.name.replace("-", " ").strip()
        if project.startswith("Users"):
            parts = project.split()
            project = "~/" + "/".join(parts[2:]) if len(parts) > 2 else "Home"
        return project

    def _extract_text_content(self, content, detailed: bool = False, thinking: bool = False) -> str:
        """Extract text from various content formats Claude uses.

        Args:
            content: The content to extract from
            detailed: If True, include tool use blocks and other metadata
            thinking: If True, include extended thinking blocks
        """
        if isinstance(content, str):
            return content
        elif isinstance(content, list):
            # Extract text from content array
            text_parts = []
            for item in content:
                if isinstance(item, dict):
                    if item.get("type") == "text":
                        text_parts.append(item.get("text", ""))
                    elif thinking and item.get("type") == "thinking":
                        thinking_text = item.get("thinking", "")
                        if thinking_text:
                            text_parts.append(f"\n💭 Thinking:\n{thinking_text}\n")
                    elif detailed and item.get("type") == "tool_use":
                        # Include tool use details in detailed mode
                        tool_name = item.get("name", "unknown")
                        tool_input = item.get("input", {})
                        text_parts.append(f"\n🔧 Using tool: {tool_name}")
                        text_parts.append(f"Input: {json.dumps(tool_input, indent=2)}\n")
            return "\n".join(text_parts)
        else:
            return str(content)

    def display_conversation(self, jsonl_path: Path, detailed: bool = False, thinking: bool = False) -> None:
        """Display a conversation in the terminal with pagination.

        Args:
            jsonl_path: Path to the JSONL file
            detailed: If True, include tool use and system messages
            thinking: If True, include extended thinking blocks
        """
        try:
            # Extract conversation
            messages = self.extract_conversation(jsonl_path, detailed=detailed, thinking=thinking)
            
            if not messages:
                print("❌ No messages found in conversation")
                return
            
            # Get session info
            session_id = self._get_session_id(jsonl_path)
            
            # Clear screen and show header
            print("\033[2J\033[H", end="")  # Clear screen
            print("=" * 60)
            print(f"📄 Viewing: {self._get_session_display_name(jsonl_path)}")
            print(f"Session: {session_id[:8]}...")
            
            # Get timestamp from first message
            first_timestamp = messages[0].get("timestamp", "")
            if first_timestamp:
                try:
                    dt = datetime.fromisoformat(first_timestamp.replace("Z", "+00:00"))
                    print(f"Date: {dt.strftime('%Y-%m-%d %H:%M:%S')}")
                except Exception:
                    pass
            
            print("=" * 60)
            print("↑↓ to scroll • Q to quit • Enter to continue\n")
            
            # Display messages with pagination
            lines_shown = 8  # Header lines
            lines_per_page = 30
            
            for i, msg in enumerate(messages):
                role = msg["role"]
                content = msg["content"]
                
                # Format role display
                if role == "user" or role == "human":
                    print(f"\n{'─' * 40}")
                    print(f"👤 HUMAN:")
                    print(f"{'─' * 40}")
                elif role == "assistant":
                    print(f"\n{'─' * 40}")
                    print(f"🤖 {self.source_config['assistant_terminal_name']}:")
                    print(f"{'─' * 40}")
                elif role == "tool_use":
                    print(f"\n🔧 TOOL USE:")
                elif role == "tool_result":
                    print(f"\n📤 TOOL RESULT:")
                elif role == "system":
                    print(f"\nℹ️ SYSTEM:")
                elif role == "thinking":
                    print(f"\n💭 THINKING:")
                else:
                    print(f"\n{role.upper()}:")
                
                # Display content (limit very long messages)
                lines = content.split('\n')
                max_lines_per_msg = 50
                
                for line_idx, line in enumerate(lines[:max_lines_per_msg]):
                    # Wrap very long lines
                    if len(line) > 100:
                        line = line[:97] + "..."
                    print(line)
                    lines_shown += 1
                    
                    # Check if we need to paginate
                    if lines_shown >= lines_per_page:
                        response = input("\n[Enter] Continue • [Q] Quit: ").strip().upper()
                        if response == "Q":
                            print("\n👋 Stopped viewing")
                            return
                        # Clear screen for next page
                        print("\033[2J\033[H", end="")
                        lines_shown = 0
                
                if len(lines) > max_lines_per_msg:
                    print(f"... [{len(lines) - max_lines_per_msg} more lines truncated]")
                    lines_shown += 1
            
            print("\n" + "=" * 60)
            print("📄 End of conversation")
            print("=" * 60)
            input("\nPress Enter to continue...")
            
        except Exception as e:
            print(f"❌ Error displaying conversation: {e}")
            input("\nPress Enter to continue...")

    def save_as_markdown(
        self, conversation: List[Dict[str, str]], session_id: str
    ) -> Optional[Path]:
        """Save conversation as clean markdown file."""
        if not conversation:
            return None

        # Get timestamp from first message
        first_timestamp = conversation[0].get("timestamp", "")
        if first_timestamp:
            try:
                # Parse ISO timestamp
                dt = datetime.fromisoformat(first_timestamp.replace("Z", "+00:00"))
                date_str = dt.strftime("%Y-%m-%d")
                time_str = dt.strftime("%H:%M:%S")
            except Exception:
                date_str = datetime.now().strftime("%Y-%m-%d")
                time_str = ""
        else:
            date_str = datetime.now().strftime("%Y-%m-%d")
            time_str = ""

        filename = f"{self.source_config['conversation_prefix']}-{date_str}-{session_id[:8]}.md"
        output_path = self.output_dir / filename

        with open(output_path, "w", encoding="utf-8") as f:
            f.write(f"# {self.source_config['conversation_title']}\n\n")
            f.write(f"Session ID: {session_id}\n")
            f.write(f"Date: {date_str}")
            if time_str:
                f.write(f" {time_str}")
            f.write("\n\n---\n\n")

            for msg in conversation:
                role = msg["role"]
                content = msg["content"]
                
                if role == "user":
                    f.write("## 👤 User\n\n")
                    f.write(f"{content}\n\n")
                elif role == "assistant":
                    f.write(f"{self.source_config['assistant_heading']}\n\n")
                    f.write(f"{content}\n\n")
                elif role == "tool_use":
                    f.write("### 🔧 Tool Use\n\n")
                    f.write(f"{content}\n\n")
                elif role == "tool_result":
                    f.write("### 📤 Tool Result\n\n")
                    f.write(f"{content}\n\n")
                elif role == "system":
                    f.write("### ℹ️ System\n\n")
                    f.write(f"{content}\n\n")
                elif role == "thinking":
                    f.write("### 💭 Thinking\n\n")
                    f.write(f"{content}\n\n")
                else:
                    f.write(f"## {role}\n\n")
                    f.write(f"{content}\n\n")
                f.write("---\n\n")

        return output_path
    
    def save_as_json(
        self, conversation: List[Dict[str, str]], session_id: str
    ) -> Optional[Path]:
        """Save conversation as JSON file."""
        if not conversation:
            return None

        # Get timestamp from first message
        first_timestamp = conversation[0].get("timestamp", "")
        if first_timestamp:
            try:
                dt = datetime.fromisoformat(first_timestamp.replace("Z", "+00:00"))
                date_str = dt.strftime("%Y-%m-%d")
            except Exception:
                date_str = datetime.now().strftime("%Y-%m-%d")
        else:
            date_str = datetime.now().strftime("%Y-%m-%d")

        filename = f"{self.source_config['conversation_prefix']}-{date_str}-{session_id[:8]}.json"
        output_path = self.output_dir / filename

        # Create JSON structure
        output = {
            "source": self.source,
            "session_id": session_id,
            "date": date_str,
            "message_count": len(conversation),
            "messages": conversation
        }

        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(output, f, indent=2, ensure_ascii=False)

        return output_path
    
    def save_as_html(
        self, conversation: List[Dict[str, str]], session_id: str
    ) -> Optional[Path]:
        """Save conversation as HTML file with syntax highlighting."""
        if not conversation:
            return None

        # Get timestamp from first message
        first_timestamp = conversation[0].get("timestamp", "")
        if first_timestamp:
            try:
                dt = datetime.fromisoformat(first_timestamp.replace("Z", "+00:00"))
                date_str = dt.strftime("%Y-%m-%d")
                time_str = dt.strftime("%H:%M:%S")
            except Exception:
                date_str = datetime.now().strftime("%Y-%m-%d")
                time_str = ""
        else:
            date_str = datetime.now().strftime("%Y-%m-%d")
            time_str = ""

        filename = f"{self.source_config['conversation_prefix']}-{date_str}-{session_id[:8]}.html"
        output_path = self.output_dir / filename

        # HTML template with modern styling
        html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{self.source_config['display_name']} Conversation - {session_id[:8]}</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 900px;
            margin: 0 auto;
            padding: 20px;
            background: #f5f5f5;
        }}
        .header {{
            background: white;
            padding: 20px;
            border-radius: 8px;
            margin-bottom: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }}
        h1 {{
            color: #2c3e50;
            margin: 0 0 10px 0;
        }}
        .metadata {{
            color: #666;
            font-size: 0.9em;
        }}
        .message {{
            background: white;
            padding: 15px 20px;
            margin-bottom: 15px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }}
        .user {{
            border-left: 4px solid #3498db;
        }}
        .assistant {{
            border-left: 4px solid #2ecc71;
        }}
        .tool_use {{
            border-left: 4px solid #f39c12;
            background: #fffbf0;
        }}
        .tool_result {{
            border-left: 4px solid #e74c3c;
            background: #fff5f5;
        }}
        .system {{
            border-left: 4px solid #95a5a6;
            background: #f8f9fa;
        }}
        .role {{
            font-weight: bold;
            margin-bottom: 10px;
            display: flex;
            align-items: center;
        }}
        .content {{
            white-space: pre-wrap;
            word-wrap: break-word;
        }}
        pre {{
            background: #f4f4f4;
            padding: 10px;
            border-radius: 4px;
            overflow-x: auto;
        }}
        code {{
            background: #f4f4f4;
            padding: 2px 4px;
            border-radius: 3px;
            font-family: 'Courier New', monospace;
        }}
    </style>
</head>
<body>
    <div class="header">
        <h1>{self.source_config['conversation_title']}</h1>
        <div class="metadata">
            <p>Session ID: {session_id}</p>
            <p>Date: {date_str} {time_str}</p>
            <p>Messages: {len(conversation)}</p>
        </div>
    </div>
"""

        with open(output_path, "w", encoding="utf-8") as f:
            f.write(html_content)
            
            for msg in conversation:
                role = msg["role"]
                content = msg["content"]
                
                # Escape HTML
                content = content.replace("&", "&amp;")
                content = content.replace("<", "&lt;")
                content = content.replace(">", "&gt;")
                
                role_display = {
                    "user": "👤 User",
                    "assistant": f"🤖 {self.source_config['assistant_name']}",
                    "tool_use": "🔧 Tool Use",
                    "tool_result": "📤 Tool Result",
                    "system": "ℹ️ System"
                }.get(role, role)
                
                f.write(f'    <div class="message {role}">\n')
                f.write(f'        <div class="role">{role_display}</div>\n')
                f.write(f'        <div class="content">{content}</div>\n')
                f.write(f'    </div>\n')
            
            f.write("\n</body>\n</html>")

        return output_path

    def save_conversation(
        self, conversation: List[Dict[str, str]], session_id: str, format: str = "markdown"
    ) -> Optional[Path]:
        """Save conversation in the specified format.
        
        Args:
            conversation: The conversation data
            session_id: Session identifier
            format: Output format ('markdown', 'json', 'html')
        """
        if format == "markdown":
            return self.save_as_markdown(conversation, session_id)
        elif format == "json":
            return self.save_as_json(conversation, session_id)
        elif format == "html":
            return self.save_as_html(conversation, session_id)
        else:
            print(f"❌ Unsupported format: {format}")
            return None

    def get_conversation_preview(self, session_path: Path) -> Tuple[str, int]:
        """Get a preview of the conversation's first real user message and message count."""
        if self.source == "copilot":
            return self._get_copilot_conversation_preview(session_path)

        try:
            first_user_msg = ""
            msg_count = 0
            
            with open(session_path, 'r', encoding='utf-8') as f:
                for line in f:
                    msg_count += 1
                    if not first_user_msg:
                        try:
                            data = json.loads(line)
                            # Check for user message
                            if data.get("type") == "user" and "message" in data:
                                msg = data["message"]
                                if msg.get("role") == "user":
                                    content = msg.get("content", "")
                                    
                                    # Handle list content (common format in Claude JSONL)
                                    if isinstance(content, list):
                                        for item in content:
                                            if isinstance(item, dict) and item.get("type") == "text":
                                                text = item.get("text", "").strip()
                                                
                                                # Skip tool results
                                                if text.startswith("tool_use_id"):
                                                    continue
                                                
                                                # Skip interruption messages
                                                if "[Request interrupted" in text:
                                                    continue
                                                
                                                # Skip Claude's session continuation messages
                                                if "session is being continued" in text.lower():
                                                    continue
                                                
                                                # Remove XML-like tags (command messages, etc)
                                                import re
                                                text = re.sub(r'<[^>]+>', '', text).strip()
                                                
                                                # Skip command outputs  
                                                if "is running" in text and "…" in text:
                                                    continue
                                                
                                                # Handle image references - extract text after them
                                                if text.startswith("[Image #"):
                                                    parts = text.split("]", 1)
                                                    if len(parts) > 1:
                                                        text = parts[1].strip()
                                                
                                                # If we have real user text, use it
                                                if text and len(text) > 3:  # Lower threshold to catch "hello"
                                                    first_user_msg = text[:100].replace('\n', ' ')
                                                    break
                                    
                                    # Handle string content (less common but possible)
                                    elif isinstance(content, str):
                                        import re
                                        content = content.strip()
                                        
                                        # Remove XML-like tags
                                        content = re.sub(r'<[^>]+>', '', content).strip()
                                        
                                        # Skip command outputs
                                        if "is running" in content and "…" in content:
                                            continue
                                        
                                        # Skip Claude's session continuation messages
                                        if "session is being continued" in content.lower():
                                            continue
                                        
                                        # Skip tool results and interruptions
                                        if not content.startswith("tool_use_id") and "[Request interrupted" not in content:
                                            if content and len(content) > 3:  # Lower threshold to catch short messages
                                                first_user_msg = content[:100].replace('\n', ' ')
                        except json.JSONDecodeError:
                            continue
                            
            return first_user_msg or "No preview available", msg_count
        except Exception as e:
            return f"Error: {str(e)[:30]}", 0

    def _get_copilot_conversation_preview(self, session_path: Path) -> Tuple[str, int]:
        """Get a preview of the first Copilot user message and message count."""
        try:
            first_user_msg = ""
            msg_count = 0

            with open(session_path, "r", encoding="utf-8") as f:
                for line in f:
                    try:
                        data = json.loads(line)
                    except json.JSONDecodeError:
                        continue

                    event_type = data.get("type")
                    if event_type in {"user.message", "assistant.message"}:
                        msg_count += 1

                    if not first_user_msg and event_type == "user.message":
                        text = self._extract_copilot_text_content(
                            data.get("data", {}).get("content", "")
                        ).strip()
                        if text:
                            first_user_msg = text[:100].replace("\n", " ")

            return first_user_msg or "No preview available", msg_count
        except Exception as e:
            return f"Error: {str(e)[:30]}", 0

    def list_recent_sessions(self, limit: int = None) -> List[Path]:
        """List recent sessions with details."""
        sessions = self.find_sessions()

        if not sessions:
            print(f"❌ {self.source_config['no_sessions_message']}")
            print(
                f"💡 Make sure you've used {self.source_config['display_name']} and have conversations saved."
            )
            return []

        print(f"\n📚 Found {len(sessions)} {self.source_config['display_name']} sessions:\n")
        print("=" * 80)

        # Show all sessions if no limit specified
        sessions_to_show = sessions[:limit] if limit else sessions
        for i, session in enumerate(sessions_to_show, 1):
            project = self._get_session_display_name(session)
            session_id = self._get_session_id(session)
            modified = datetime.fromtimestamp(session.stat().st_mtime)

            # Get file size
            size = session.stat().st_size
            size_kb = size / 1024
            
            # Get preview and message count
            preview, msg_count = self.get_conversation_preview(session)

            # Print formatted info
            print(f"\n{i}. 📁 {project}")
            print(f"   📄 Session: {session_id[:8]}...")
            print(f"   📅 Modified: {modified.strftime('%Y-%m-%d %H:%M')}")
            print(f"   💬 Messages: {msg_count}")
            print(f"   💾 Size: {size_kb:.1f} KB")
            print(f"   📝 Preview: \"{preview}...\"")

        print("\n" + "=" * 80)
        return sessions[:limit]

    def extract_multiple(
        self, sessions: List[Path], indices: List[int],
        format: str = "markdown", detailed: bool = False, thinking: bool = False
    ) -> Tuple[int, int]:
        """Extract multiple sessions by index.

        Args:
            sessions: List of session paths
            indices: Indices to extract
            format: Output format ('markdown', 'json', 'html')
            detailed: If True, include tool use and system messages
            thinking: If True, include extended thinking blocks
        """
        success = 0
        total = len(indices)

        for idx in indices:
            if 0 <= idx < len(sessions):
                session_path = sessions[idx]
                conversation = self.extract_conversation(session_path, detailed=detailed, thinking=thinking)
                if conversation:
                    output_path = self.save_conversation(
                        conversation, self._get_session_id(session_path), format=format
                    )
                    success += 1
                    msg_count = len(conversation)
                    print(
                        f"✅ {success}/{total}: {output_path.name} "
                        f"({msg_count} messages)"
                    )
                else:
                    print(f"⏭️  Skipped session {idx + 1} (no conversation)")
            else:
                print(f"❌ Invalid session number: {idx + 1}")

        return success, total


def main():
    parser = argparse.ArgumentParser(
        description="Extract Claude Code conversations to clean markdown files",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --list                    # List all available sessions
  %(prog)s --extract 1               # Extract the most recent session
  %(prog)s --extract 1,3,5           # Extract specific sessions
  %(prog)s --recent 5                # Extract 5 most recent sessions
  %(prog)s --all                     # Extract all sessions
  %(prog)s --output ~/my-logs        # Specify output directory
  %(prog)s --search "python error"   # Search conversations
  %(prog)s --search-regex "import.*" # Search with regex
  %(prog)s --format json --all       # Export all as JSON
  %(prog)s --format html --extract 1 # Export session 1 as HTML
  %(prog)s --detailed --extract 1    # Include tool use & system messages
  %(prog)s --thinking --extract 1    # Include extended thinking blocks
        """,
    )
    parser.add_argument("--list", action="store_true", help="List recent sessions")
    parser.add_argument(
        "--extract",
        type=str,
        help="Extract specific session(s) by number (comma-separated)",
    )
    parser.add_argument(
        "--all", "--logs", action="store_true", help="Extract all sessions"
    )
    parser.add_argument(
        "--recent", type=int, help="Extract N most recent sessions", default=0
    )
    parser.add_argument(
        "--output", type=str, help="Output directory for markdown files"
    )
    parser.add_argument(
        "--limit", type=int, help="Limit for --list command (default: show all)", default=None
    )
    parser.add_argument(
        "--interactive",
        "-i",
        "--start",
        "-s",
        action="store_true",
        help="Launch interactive UI for easy extraction",
    )
    parser.add_argument(
        "--export",
        type=str,
        help="Export mode: 'logs' for interactive UI",
    )

    # Search arguments
    parser.add_argument(
        "--search", type=str, help="Search conversations for text (smart search)"
    )
    parser.add_argument(
        "--search-regex", type=str, help="Search conversations using regex pattern"
    )
    parser.add_argument(
        "--search-date-from", type=str, help="Filter search from date (YYYY-MM-DD)"
    )
    parser.add_argument(
        "--search-date-to", type=str, help="Filter search to date (YYYY-MM-DD)"
    )
    parser.add_argument(
        "--search-speaker",
        choices=["human", "assistant", "both"],
        default="both",
        help="Filter search by speaker",
    )
    parser.add_argument(
        "--case-sensitive", action="store_true", help="Make search case-sensitive"
    )
    
    # Export format arguments
    parser.add_argument(
        "--format",
        choices=["markdown", "json", "html"],
        default="markdown",
        help="Output format for exported conversations (default: markdown)"
    )
    parser.add_argument(
        "--detailed",
        action="store_true",
        help="Include tool use, MCP responses, and system messages in export"
    )
    parser.add_argument(
        "--thinking",
        action="store_true",
        help="Include extended thinking blocks in export"
    )
    parser.add_argument(
        "--copilot",
        action="store_true",
        help="Extract and search GitHub Copilot CLI sessions from ~/.copilot/session-state",
    )

    args = parser.parse_args()
    source = "copilot" if args.copilot else "claude"

    # Handle interactive mode
    if args.interactive or (args.export and args.export.lower() == "logs"):
        try:
            from .interactive_ui import main as interactive_main
        except ImportError:
            from interactive_ui import main as interactive_main

        interactive_main(source=source)
        return

    # Initialize extractor with optional output directory
    extractor = ClaudeConversationExtractor(args.output, source=source)

    # Handle search mode
    if args.search or args.search_regex:
        from datetime import datetime

        try:
            from .search_conversations import ConversationSearcher
        except ImportError:
            from search_conversations import ConversationSearcher

        searcher = ConversationSearcher(source=source)

        # Determine search mode and query
        if args.search_regex:
            query = args.search_regex
            mode = "regex"
        else:
            query = args.search
            mode = "smart"

        # Parse date filters
        date_from = None
        date_to = None
        if args.search_date_from:
            try:
                date_from = datetime.strptime(args.search_date_from, "%Y-%m-%d")
            except ValueError:
                print(f"❌ Invalid date format: {args.search_date_from}")
                return

        if args.search_date_to:
            try:
                date_to = datetime.strptime(args.search_date_to, "%Y-%m-%d")
            except ValueError:
                print(f"❌ Invalid date format: {args.search_date_to}")
                return

        # Speaker filter
        speaker_filter = None if args.search_speaker == "both" else args.search_speaker

        # Perform search
        print(f"🔍 Searching for: {query}")
        results = searcher.search(
            query=query,
            mode=mode,
            date_from=date_from,
            date_to=date_to,
            speaker_filter=speaker_filter,
            case_sensitive=args.case_sensitive,
            max_results=30,
        )

        if not results:
            print("❌ No matches found.")
            return

        print(f"\n✅ Found {len(results)} matches across conversations:")

        # Group and display results
        results_by_file = {}
        for result in results:
            if result.file_path not in results_by_file:
                results_by_file[result.file_path] = []
            results_by_file[result.file_path].append(result)

        # Store file paths for potential viewing
        file_paths_list = []
        for file_path, file_results in results_by_file.items():
            file_paths_list.append(file_path)
            print(f"\n{len(file_paths_list)}. 📄 {file_path.parent.name} ({len(file_results)} matches)")
            # Show first match preview
            first = file_results[0]
            print(f"   {first.speaker}: {first.matched_content[:100]}...")

        # Offer to view conversations
        if file_paths_list:
            print("\n" + "=" * 60)
            try:
                view_choice = input("\nView a conversation? Enter number (1-{}) or press Enter to skip: ".format(
                    len(file_paths_list))).strip()
                
                if view_choice.isdigit():
                    view_num = int(view_choice)
                    if 1 <= view_num <= len(file_paths_list):
                        selected_path = file_paths_list[view_num - 1]
                        extractor.display_conversation(selected_path, detailed=args.detailed, thinking=args.thinking)

                        # Offer to extract after viewing
                        extract_choice = input("\n📤 Extract this conversation? (y/N): ").strip().lower()
                        if extract_choice == 'y':
                            conversation = extractor.extract_conversation(selected_path, detailed=args.detailed, thinking=args.thinking)
                            if conversation:
                                session_id = extractor._get_session_id(selected_path)
                                if args.format == "json":
                                    output = extractor.save_as_json(conversation, session_id)
                                elif args.format == "html":
                                    output = extractor.save_as_html(conversation, session_id)
                                else:
                                    output = extractor.save_as_markdown(conversation, session_id)
                                print(f"✅ Saved: {output.name}")
            except (EOFError, KeyboardInterrupt):
                print("\n👋 Cancelled")
        
        return

    # Default action is to list sessions
    if args.list or (
        not args.extract
        and not args.all
        and not args.recent
        and not args.search
        and not args.search_regex
    ):
        sessions = extractor.list_recent_sessions(args.limit)

        if sessions and not args.list:
            print("\nTo extract conversations:")
            print("  claude-extract --extract <number>      # Extract specific session")
            print("  claude-extract --recent 5              # Extract 5 most recent")
            print("  claude-extract --all                   # Extract all sessions")
            if args.copilot:
                print("  claude-extract --copilot --extract <number>")

    elif args.extract:
        sessions = extractor.find_sessions()

        # Parse comma-separated indices
        indices = []
        for num in args.extract.split(","):
            try:
                idx = int(num.strip()) - 1  # Convert to 0-based index
                indices.append(idx)
            except ValueError:
                print(f"❌ Invalid session number: {num}")
                continue

        if indices:
            print(f"\n📤 Extracting {len(indices)} session(s) as {args.format.upper()}...")
            if args.detailed:
                print("📋 Including detailed tool use and system messages")
            if args.thinking:
                print("💭 Including extended thinking blocks")
            success, total = extractor.extract_multiple(
                sessions, indices, format=args.format, detailed=args.detailed, thinking=args.thinking
            )
            print(f"\n✅ Successfully extracted {success}/{total} sessions")

    elif args.recent:
        sessions = extractor.find_sessions()
        limit = min(args.recent, len(sessions))
        print(f"\n📤 Extracting {limit} most recent sessions as {args.format.upper()}...")
        if args.detailed:
            print("📋 Including detailed tool use and system messages")
        if args.thinking:
            print("💭 Including extended thinking blocks")

        indices = list(range(limit))
        success, total = extractor.extract_multiple(
            sessions, indices, format=args.format, detailed=args.detailed, thinking=args.thinking
        )
        print(f"\n✅ Successfully extracted {success}/{total} sessions")

    elif args.all:
        sessions = extractor.find_sessions()
        print(f"\n📤 Extracting all {len(sessions)} sessions as {args.format.upper()}...")
        if args.detailed:
            print("📋 Including detailed tool use and system messages")
        if args.thinking:
            print("💭 Including extended thinking blocks")

        indices = list(range(len(sessions)))
        success, total = extractor.extract_multiple(
            sessions, indices, format=args.format, detailed=args.detailed, thinking=args.thinking
        )
        print(f"\n✅ Successfully extracted {success}/{total} sessions")


def launch_interactive():
    """Launch the interactive UI directly, or handle search if specified."""
    import sys
    
    # If no arguments provided, launch interactive UI
    if len(sys.argv) == 1:
        try:
            from .interactive_ui import main as interactive_main
        except ImportError:
            from interactive_ui import main as interactive_main
        interactive_main()
    # Check if 'search' was passed as an argument
    elif len(sys.argv) > 1 and sys.argv[1] == 'search':
        # Launch real-time search with viewing capability
        try:
            from .realtime_search import RealTimeSearch, create_smart_searcher
            from .search_conversations import ConversationSearcher
        except ImportError:
            from realtime_search import RealTimeSearch, create_smart_searcher
            from search_conversations import ConversationSearcher
        
        # Initialize components
        source = "copilot" if "--copilot" in sys.argv[2:] else "claude"
        extractor = ClaudeConversationExtractor(source=source)
        searcher = ConversationSearcher(source=source)
        smart_searcher = create_smart_searcher(searcher)
        
        # Run search
        rts = RealTimeSearch(smart_searcher, extractor)
        selected_file = rts.run()
        
        if selected_file:
            # View the selected conversation
            extractor.display_conversation(selected_file)
            
            # Offer to extract
            try:
                extract_choice = input("\n📤 Extract this conversation? (y/N): ").strip().lower()
                if extract_choice == 'y':
                    conversation = extractor.extract_conversation(selected_file)
                    if conversation:
                        session_id = extractor._get_session_id(selected_file)
                        output = extractor.save_as_markdown(conversation, session_id)
                        print(f"✅ Saved: {output.name}")
            except (EOFError, KeyboardInterrupt):
                print("\n👋 Cancelled")
    else:
        # If other arguments are provided, run the normal CLI
        main()


if __name__ == "__main__":
    main()

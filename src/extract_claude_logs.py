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
from typing import Dict, List, Optional, Tuple


class ClaudeConversationExtractor:
    """Extract and convert Claude Code conversations from JSONL to markdown."""

    def __init__(self, output_dir: Optional[Path] = None):
        """Initialize the extractor with Claude's directory and output location."""
        self.claude_dir = Path.home() / ".claude" / "projects"

        if output_dir:
            self.output_dir = Path(output_dir)
            self.output_dir.mkdir(parents=True, exist_ok=True)
        else:
            # Try multiple possible output directories
            possible_dirs = [
                Path.home() / "Desktop" / "Claude logs",
                Path.home() / "Documents" / "Claude logs",
                Path.home() / "Claude logs",
                Path.cwd() / "claude-logs",
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
                # Fallback to current directory
                self.output_dir = Path.cwd() / "claude-logs"
                self.output_dir.mkdir(exist_ok=True)

        print(f"📁 Saving logs to: {self.output_dir}")

    def find_sessions(self, project_path: Optional[str] = None) -> List[Path]:
        """Find all JSONL session files, sorted by most recent first."""
        if project_path:
            search_dir = self.claude_dir / project_path
        else:
            search_dir = self.claude_dir

        sessions = []
        if search_dir.exists():
            for jsonl_file in search_dir.rglob("*.jsonl"):
                sessions.append(jsonl_file)
        return sorted(sessions, key=lambda x: x.stat().st_mtime, reverse=True)

    def extract_conversation(self, jsonl_path: Path, detailed: bool = False) -> List[Dict[str, str]]:
        """Extract conversation messages from a JSONL file.
        
        Args:
            jsonl_path: Path to the JSONL file
            detailed: If True, include tool use, MCP responses, and system messages
        """
        conversation = []

        try:
            with open(jsonl_path, "r", encoding="utf-8") as f:
                for line in f:
                    try:
                        entry = json.loads(line.strip())

                        # Extract user messages
                        if entry.get("type") == "user" and "message" in entry:
                            msg = entry["message"]
                            if isinstance(msg, dict) and msg.get("role") == "user":
                                content = msg.get("content", "")
                                text = self._extract_text_content(content)

                                if text and text.strip():
                                    conversation.append(
                                        {
                                            "role": "user",
                                            "content": text,
                                            "timestamp": entry.get("timestamp", ""),
                                        }
                                    )

                        # Extract assistant messages
                        elif entry.get("type") == "assistant" and "message" in entry:
                            msg = entry["message"]
                            if isinstance(msg, dict) and msg.get("role") == "assistant":
                                content = msg.get("content", [])
                                timestamp = entry.get("timestamp", "")

                                if detailed and isinstance(content, list):
                                    # Split assistant content into text + tool_use entries
                                    text_parts = []
                                    for item in content:
                                        if isinstance(item, dict):
                                            if item.get("type") == "text":
                                                text_parts.append(item.get("text", ""))
                                            elif item.get("type") == "tool_use":
                                                # Flush accumulated text first
                                                if text_parts:
                                                    joined = "\n".join(text_parts).strip()
                                                    if joined:
                                                        conversation.append({
                                                            "role": "assistant",
                                                            "content": joined,
                                                            "timestamp": timestamp,
                                                        })
                                                    text_parts = []
                                                # Add tool_use as separate entry with structured data
                                                tool_name = item.get("name", "unknown")
                                                tool_input = item.get("input", {})
                                                conversation.append({
                                                    "role": "tool_use",
                                                    "tool_name": tool_name,
                                                    "tool_input": tool_input,
                                                    "content": f"🔧 Tool: {tool_name}\nInput: {json.dumps(tool_input, indent=2, ensure_ascii=False)}",
                                                    "timestamp": timestamp,
                                                })
                                    # Flush remaining text
                                    if text_parts:
                                        joined = "\n".join(text_parts).strip()
                                        if joined:
                                            conversation.append({
                                                "role": "assistant",
                                                "content": joined,
                                                "timestamp": timestamp,
                                            })
                                else:
                                    text = self._extract_text_content(content, detailed=detailed)
                                    if text and text.strip():
                                        conversation.append({
                                            "role": "assistant",
                                            "content": text,
                                            "timestamp": timestamp,
                                        })

                        # Extract tool results from user messages in detailed mode
                        if detailed and entry.get("type") == "user" and "message" in entry:
                            msg = entry["message"]
                            if isinstance(msg, dict) and isinstance(msg.get("content"), list):
                                for item in msg["content"]:
                                    if isinstance(item, dict) and item.get("type") == "tool_result":
                                        result_content = item.get("content", "")
                                        if isinstance(result_content, list):
                                            result_content = "\n".join(
                                                sub.get("text", "") for sub in result_content
                                                if isinstance(sub, dict) and sub.get("type") == "text"
                                            )
                                        if result_content and str(result_content).strip():
                                            conversation.append({
                                                "role": "tool_result",
                                                "content": f"📤 Result:\n{result_content}",
                                                "timestamp": entry.get("timestamp", ""),
                                            })

                    except json.JSONDecodeError:
                        continue
                    except Exception:
                        # Silently skip problematic entries
                        continue

        except Exception as e:
            print(f"❌ Error reading file {jsonl_path}: {e}")

        return conversation

    def _extract_text_content(self, content, detailed: bool = False) -> str:
        """Extract text from various content formats Claude uses.
        
        Args:
            content: The content to extract from
            detailed: If True, include tool use blocks and other metadata
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
                    elif detailed and item.get("type") == "tool_use":
                        # Include tool use details in detailed mode
                        tool_name = item.get("name", "unknown")
                        tool_input = item.get("input", {})
                        text_parts.append(f"\n🔧 Using tool: {tool_name}")
                        text_parts.append(f"Input: {json.dumps(tool_input, indent=2, ensure_ascii=False)}\n")
            return "\n".join(text_parts)
        else:
            return str(content)

    def display_conversation(self, jsonl_path: Path, detailed: bool = False) -> None:
        """Display a conversation in the terminal with pagination.
        
        Args:
            jsonl_path: Path to the JSONL file
            detailed: If True, include tool use and system messages
        """
        try:
            # Extract conversation
            messages = self.extract_conversation(jsonl_path, detailed=detailed)
            
            if not messages:
                print("❌ No messages found in conversation")
                return
            
            # Get session info
            session_id = jsonl_path.stem
            
            # Clear screen and show header
            print("\033[2J\033[H", end="")  # Clear screen
            print("=" * 60)
            print(f"📄 Viewing: {jsonl_path.parent.name}")
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
                    print(f"🤖 CLAUDE:")
                    print(f"{'─' * 40}")
                elif role == "tool_use":
                    print(f"\n🔧 TOOL USE:")
                elif role == "tool_result":
                    print(f"\n📤 TOOL RESULT:")
                elif role == "system":
                    print(f"\nℹ️ SYSTEM:")
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

        filename = f"claude-conversation-{date_str}-{session_id[:8]}.md"
        output_path = self.output_dir / filename

        with open(output_path, "w", encoding="utf-8") as f:
            f.write("# Claude Conversation Log\n\n")
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
                    f.write("## 🤖 Claude\n\n")
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

        filename = f"claude-conversation-{date_str}-{session_id[:8]}.json"
        output_path = self.output_dir / filename

        # Create JSON structure
        output = {
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

        filename = f"claude-conversation-{date_str}-{session_id[:8]}.html"
        output_path = self.output_dir / filename

        # File extension to highlight.js language mapping
        ext_to_lang = {
            '.py': 'python', '.js': 'javascript', '.ts': 'typescript',
            '.tsx': 'typescript', '.jsx': 'javascript', '.go': 'go',
            '.rs': 'rust', '.java': 'java', '.rb': 'ruby', '.php': 'php',
            '.c': 'c', '.cpp': 'cpp', '.h': 'c', '.hpp': 'cpp',
            '.cs': 'csharp', '.swift': 'swift', '.kt': 'kotlin',
            '.sh': 'bash', '.zsh': 'bash', '.bash': 'bash',
            '.html': 'html', '.htm': 'html', '.xml': 'xml',
            '.css': 'css', '.scss': 'scss', '.less': 'less',
            '.json': 'json', '.yaml': 'yaml', '.yml': 'yaml',
            '.toml': 'toml', '.ini': 'ini', '.cfg': 'ini',
            '.md': 'markdown', '.sql': 'sql', '.r': 'r',
            '.lua': 'lua', '.vim': 'vim', '.dockerfile': 'dockerfile',
            '.tf': 'hcl', '.proto': 'protobuf', '.graphql': 'graphql',
        }

        import html as html_module
        from pathlib import PurePosixPath

        def _get_lang(file_path_str):
            ext = PurePosixPath(file_path_str).suffix.lower()
            return ext_to_lang.get(ext, '')

        def _escape(text):
            return html_module.escape(str(text))

        def _render_tool_use_html(msg):
            """Render tool_use message with enhanced formatting for Write/Edit tools."""
            tool_name = msg.get("tool_name", "")
            tool_input = msg.get("tool_input", {})

            if tool_name == "Write" or tool_name == "write":
                file_path = tool_input.get("file_path", tool_input.get("filePath", ""))
                content = tool_input.get("content", "")
                lang = _get_lang(file_path)
                lang_class = f' class="language-{lang}"' if lang else ''
                line_count = content.count('\n') + 1
                code_block = f'<pre><code{lang_class}>{_escape(content)}</code></pre>'
                if line_count > 30:
                    return (
                        f'<div class="tool-header">📝 Write → <code>{_escape(file_path)}</code></div>\n'
                        f'<details>\n'
                        f'<summary>File content ({line_count} lines) — click to expand</summary>\n'
                        f'{code_block}\n'
                        f'</details>'
                    )
                return (
                    f'<div class="tool-header">📝 Write → <code>{_escape(file_path)}</code></div>\n'
                    f'{code_block}'
                )

            elif tool_name == "Edit" or tool_name == "edit":
                file_path = tool_input.get("file_path", tool_input.get("filePath", ""))
                old_str = tool_input.get("old_string", tool_input.get("oldString", ""))
                new_str = tool_input.get("new_string", tool_input.get("newString", ""))
                lang = _get_lang(file_path)
                lang_label = f' ({lang})' if lang else ''

                diff_html = f'<div class="tool-header">✏️ Edit → <code>{_escape(file_path)}</code>{lang_label}</div>\n'
                diff_html += '<div class="diff-container">\n'

                # Render old lines (removed)
                if old_str:
                    for line in old_str.split('\n'):
                        diff_html += f'<div class="diff-line diff-removed">- {_escape(line)}</div>\n'

                # Render new lines (added)
                if new_str:
                    for line in new_str.split('\n'):
                        diff_html += f'<div class="diff-line diff-added">+ {_escape(line)}</div>\n'

                diff_html += '</div>'
                return diff_html

            elif tool_name in ("Read", "read", "Bash", "bash", "Grep", "grep", "Glob", "glob"):
                # Compact display for common read-only tools
                parts = [f'<div class="tool-header">🔧 {_escape(tool_name)}</div>']
                for k, v in tool_input.items():
                    val = _escape(str(v)) if not isinstance(v, str) else _escape(v)
                    parts.append(f'<div class="tool-param"><span class="param-key">{_escape(k)}:</span> {val}</div>')
                return '\n'.join(parts)

            elif tool_name in ("Task", "task"):
                # Task/agent tool — show description + collapsible prompt
                desc = tool_input.get("description", "")
                prompt = tool_input.get("prompt", "")
                subagent = tool_input.get("subagent_type", "")
                header = f'<div class="tool-header">🤖 Task'
                if subagent:
                    header += f' ({_escape(subagent)})'
                if desc:
                    header += f' — {_escape(desc)}'
                header += '</div>\n'
                if prompt:
                    prompt_lines = prompt.count('\n') + 1
                    if prompt_lines > 10:
                        return (
                            f'{header}'
                            f'<details>\n'
                            f'<summary>Prompt ({prompt_lines} lines) — click to expand</summary>\n'
                            f'<pre><code>{_escape(prompt)}</code></pre>\n'
                            f'</details>'
                        )
                    return f'{header}<pre><code>{_escape(prompt)}</code></pre>'
                return header

            else:
                # Generic tool display
                content_json = json.dumps(tool_input, indent=2, ensure_ascii=False)
                line_count = content_json.count('\n') + 1
                if line_count > 20:
                    return (
                        f'<div class="tool-header">🔧 {_escape(tool_name)}</div>\n'
                        f'<details>\n'
                        f'<summary>Parameters ({line_count} lines) — click to expand</summary>\n'
                        f'<pre><code class="language-json">{_escape(content_json)}</code></pre>\n'
                        f'</details>'
                    )
                return (
                    f'<div class="tool-header">🔧 {_escape(tool_name)}</div>\n'
                    f'<pre><code class="language-json">{_escape(content_json)}</code></pre>'
                )

        # HTML template — Anthropic brand styling
        html_content = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Claude Conversation - {session_id[:8]}</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;500;600;700&family=Lora:ital,wght@0,400;0,500;1,400&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css">
    <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/marked@14.0.0/marked.min.js"></script>
    <style>
        :root {{
            --dark: #141413;
            --light: #faf9f5;
            --mid-gray: #b0aea5;
            --light-gray: #e8e6dc;
            --orange: #d97757;
            --blue: #6a9bcc;
            --green: #788c5d;
        }}
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{
            font-family: 'Lora', Georgia, 'Noto Serif SC', serif;
            line-height: 1.7;
            color: var(--dark);
            max-width: 960px;
            margin: 0 auto;
            padding: 32px 20px;
            background: var(--light);
        }}
        h1, h2, h3, .role {{
            font-family: 'Poppins', Arial, 'Noto Sans SC', sans-serif;
        }}
        .header {{
            background: var(--dark);
            color: var(--light);
            padding: 32px 28px;
            border-radius: 12px;
            margin-bottom: 28px;
        }}
        .header h1 {{
            font-size: 1.5em;
            font-weight: 600;
            margin-bottom: 12px;
            letter-spacing: -0.01em;
        }}
        .header .metadata {{
            color: var(--mid-gray);
            font-family: 'Poppins', Arial, sans-serif;
            font-size: 0.82em;
            line-height: 1.8;
        }}
        .message {{
            background: white;
            padding: 18px 22px;
            margin-bottom: 14px;
            border-radius: 10px;
            border: 1px solid var(--light-gray);
        }}
        .user {{
            border-left: 4px solid var(--blue);
        }}
        .assistant {{
            border-left: 4px solid var(--green);
        }}
        .tool_use {{
            border-left: 4px solid var(--orange);
            background: #fdfbf8;
        }}
        .tool_result {{
            border-left: 4px solid var(--mid-gray);
            background: #fcfcfa;
        }}
        .system {{
            border-left: 4px solid var(--light-gray);
            background: #fafaf7;
        }}
        .role {{
            font-weight: 600;
            font-size: 0.85em;
            text-transform: uppercase;
            letter-spacing: 0.04em;
            margin-bottom: 10px;
            color: var(--dark);
            opacity: 0.7;
        }}
        .content {{
            white-space: pre-wrap;
            word-wrap: break-word;
            font-size: 0.95em;
        }}
        .tool-content {{
            word-wrap: break-word;
            font-size: 0.95em;
        }}
        .tool-header {{
            font-family: 'Poppins', Arial, sans-serif;
            font-weight: 600;
            font-size: 0.88em;
            margin-bottom: 10px;
            color: var(--dark);
            opacity: 0.8;
        }}
        .tool-header code {{
            background: var(--light-gray);
            color: var(--dark);
            padding: 2px 8px;
            border-radius: 4px;
            font-size: 0.9em;
        }}
        .tool-param {{
            font-family: 'SF Mono', 'Fira Code', monospace;
            font-size: 0.85em;
            padding: 3px 0;
            color: var(--dark);
            opacity: 0.75;
        }}
        .param-key {{
            color: var(--orange);
            font-weight: 600;
        }}
        /* Diff styles */
        .diff-container {{
            font-family: 'SF Mono', 'Fira Code', 'Courier New', monospace;
            font-size: 0.83em;
            border: 1px solid var(--light-gray);
            border-radius: 8px;
            overflow: hidden;
            margin: 10px 0;
        }}
        .diff-line {{
            padding: 2px 12px;
            white-space: pre-wrap;
            word-wrap: break-word;
        }}
        .diff-removed {{
            background: #fce8e6;
            color: #8c1d18;
        }}
        .diff-added {{
            background: #e8f5e9;
            color: #1b5e20;
        }}
        pre {{
            background: #f3f2ed;
            padding: 14px;
            border-radius: 8px;
            overflow-x: auto;
            margin: 10px 0;
            border: 1px solid var(--light-gray);
        }}
        pre code {{
            background: none;
            padding: 0;
            font-size: 0.85em;
        }}
        code {{
            background: var(--light-gray);
            padding: 2px 6px;
            border-radius: 4px;
            font-family: 'SF Mono', 'Fira Code', 'Courier New', monospace;
            font-size: 0.88em;
        }}
        /* Scrollbar */
        ::-webkit-scrollbar {{ width: 6px; height: 6px; }}
        ::-webkit-scrollbar-track {{ background: var(--light); }}
        ::-webkit-scrollbar-thumb {{ background: var(--mid-gray); border-radius: 3px; }}
        /* Collapsible sections */
        details {{
            margin: 8px 0;
        }}
        details summary {{
            cursor: pointer;
            font-family: 'Poppins', Arial, sans-serif;
            font-size: 0.83em;
            font-weight: 500;
            color: var(--mid-gray);
            padding: 4px 0;
            user-select: none;
            transition: color 0.15s;
        }}
        details summary:hover {{
            color: var(--dark);
        }}
        details[open] summary {{
            margin-bottom: 6px;
        }}
        /* Markdown rendered content */
        .markdown-content {{
            font-size: 0.95em;
            line-height: 1.75;
        }}
        .markdown-content p {{
            margin: 0.4em 0;
        }}
        .markdown-content h1, .markdown-content h2, .markdown-content h3,
        .markdown-content h4, .markdown-content h5, .markdown-content h6 {{
            font-family: 'Poppins', Arial, sans-serif;
            margin: 0.8em 0 0.4em;
            line-height: 1.3;
        }}
        .markdown-content h1 {{ font-size: 1.3em; }}
        .markdown-content h2 {{ font-size: 1.15em; }}
        .markdown-content h3 {{ font-size: 1.05em; }}
        .markdown-content ul, .markdown-content ol {{
            padding-left: 1.5em;
            margin: 0.4em 0;
        }}
        .markdown-content li {{
            margin: 0.2em 0;
        }}
        .markdown-content blockquote {{
            border-left: 3px solid var(--mid-gray);
            padding: 0.3em 0 0.3em 1em;
            margin: 0.5em 0;
            color: #555;
        }}
        .markdown-content table {{
            border-collapse: collapse;
            margin: 0.5em 0;
            font-size: 0.92em;
        }}
        .markdown-content th, .markdown-content td {{
            border: 1px solid var(--light-gray);
            padding: 6px 12px;
            text-align: left;
        }}
        .markdown-content th {{
            background: #f3f2ed;
            font-weight: 600;
        }}
        .markdown-content img {{
            max-width: 100%;
            border-radius: 6px;
        }}
        .markdown-content hr {{
            border: none;
            border-top: 1px solid var(--light-gray);
            margin: 1em 0;
        }}
        .markdown-content pre {{
            margin: 0.5em 0;
        }}
        .markdown-content > pre:first-child {{
            margin-top: 0;
        }}
    </style>
</head>
<body>
    <div class="header">
        <h1>Claude Conversation Log</h1>
        <div class="metadata">
            <p>Session: {session_id}</p>
            <p>Date: {date_str} {time_str}</p>
            <p>Messages: {len(conversation)}</p>
        </div>
    </div>
"""

        with open(output_path, "w", encoding="utf-8") as f:
            f.write(html_content)

            for msg in conversation:
                role = msg["role"]

                role_display = {
                    "user": "Human",
                    "assistant": "Claude",
                    "tool_use": "Tool Use",
                    "tool_result": "Tool Result",
                    "system": "System"
                }.get(role, role)

                f.write(f'    <div class="message {role}">\n')
                f.write(f'        <div class="role">{role_display}</div>\n')

                if role == "tool_use" and msg.get("tool_name"):
                    # Enhanced rendering for tool_use
                    f.write(f'        <div class="tool-content">{_render_tool_use_html(msg)}</div>\n')
                elif role in ("assistant", "user"):
                    # Markdown rendering for assistant and user messages
                    content = _escape(msg["content"])
                    f.write(f'        <div class="markdown-content">{content}</div>\n')
                elif role == "tool_result":
                    # Collapsible for long tool results
                    raw = msg["content"]
                    lines = raw.split('\n')
                    line_count = len(lines)
                    if line_count > 15:
                        preview = _escape('\n'.join(lines[:3]))
                        full = _escape(raw)
                        f.write(f'        <details class="content">\n')
                        f.write(f'            <summary>Result ({line_count} lines) — click to expand</summary>\n')
                        f.write(f'            <pre><code>{full}</code></pre>\n')
                        f.write(f'        </details>\n')
                    else:
                        content = _escape(raw)
                        f.write(f'        <div class="content">{content}</div>\n')
                else:
                    content = _escape(msg["content"])
                    f.write(f'        <div class="content">{content}</div>\n')

                f.write(f'    </div>\n')

            f.write("""
    <script>
    // Configure marked with highlight.js integration
    marked.setOptions({
        highlight: function(code, lang) {
            if (lang && hljs.getLanguage(lang)) {
                return hljs.highlight(code, {language: lang}).value;
            }
            return hljs.highlightAuto(code).value;
        },
        breaks: true,
        gfm: true
    });

    // Render markdown content
    document.querySelectorAll('.markdown-content').forEach(function(el) {
        var raw = el.textContent;
        el.innerHTML = marked.parse(raw);
    });

    // Highlight code blocks not handled by marked (tool_use, tool_result, etc.)
    document.querySelectorAll('pre code[class^="language-"]').forEach(function(block) {
        if (!block.dataset.highlighted) {
            hljs.highlightElement(block);
        }
    });
    </script>
</body>
</html>""")

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

    def list_recent_sessions(self, limit: int = None) -> List[Path]:
        """List recent sessions with details."""
        sessions = self.find_sessions()

        if not sessions:
            print("❌ No Claude sessions found in ~/.claude/projects/")
            print("💡 Make sure you've used Claude Code and have conversations saved.")
            return []

        print(f"\n📚 Found {len(sessions)} Claude sessions:\n")
        print("=" * 80)

        # Show all sessions if no limit specified
        sessions_to_show = sessions[:limit] if limit else sessions
        for i, session in enumerate(sessions_to_show, 1):
            # Clean up project name (remove hyphens, make readable)
            project = session.parent.name.replace('-', ' ').strip()
            if project.startswith("Users"):
                project = "~/" + "/".join(project.split()[2:]) if len(project.split()) > 2 else "Home"
            
            session_id = session.stem
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
        format: str = "markdown", detailed: bool = False
    ) -> Tuple[int, int]:
        """Extract multiple sessions by index.
        
        Args:
            sessions: List of session paths
            indices: Indices to extract
            format: Output format ('markdown', 'json', 'html')
            detailed: If True, include tool use and system messages
        """
        success = 0
        total = len(indices)

        for idx in indices:
            if 0 <= idx < len(sessions):
                session_path = sessions[idx]
                conversation = self.extract_conversation(session_path, detailed=detailed)
                if conversation:
                    output_path = self.save_conversation(conversation, session_path.stem, format=format)
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

    args = parser.parse_args()

    # Handle interactive mode
    if args.interactive or (args.export and args.export.lower() == "logs"):
        from interactive_ui import main as interactive_main

        interactive_main()
        return

    # Initialize extractor with optional output directory
    extractor = ClaudeConversationExtractor(args.output)

    # Handle search mode
    if args.search or args.search_regex:
        from datetime import datetime

        from search_conversations import ConversationSearcher

        searcher = ConversationSearcher()

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
                        extractor.display_conversation(selected_path, detailed=args.detailed)
                        
                        # Offer to extract after viewing
                        extract_choice = input("\n📤 Extract this conversation? (y/N): ").strip().lower()
                        if extract_choice == 'y':
                            conversation = extractor.extract_conversation(selected_path, detailed=args.detailed)
                            if conversation:
                                session_id = selected_path.stem
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
            success, total = extractor.extract_multiple(
                sessions, indices, format=args.format, detailed=args.detailed
            )
            print(f"\n✅ Successfully extracted {success}/{total} sessions")

    elif args.recent:
        sessions = extractor.find_sessions()
        limit = min(args.recent, len(sessions))
        print(f"\n📤 Extracting {limit} most recent sessions as {args.format.upper()}...")
        if args.detailed:
            print("📋 Including detailed tool use and system messages")

        indices = list(range(limit))
        success, total = extractor.extract_multiple(
            sessions, indices, format=args.format, detailed=args.detailed
        )
        print(f"\n✅ Successfully extracted {success}/{total} sessions")

    elif args.all:
        sessions = extractor.find_sessions()
        print(f"\n📤 Extracting all {len(sessions)} sessions as {args.format.upper()}...")
        if args.detailed:
            print("📋 Including detailed tool use and system messages")

        indices = list(range(len(sessions)))
        success, total = extractor.extract_multiple(
            sessions, indices, format=args.format, detailed=args.detailed
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
        extractor = ClaudeConversationExtractor()
        searcher = ConversationSearcher()
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
                        session_id = selected_file.stem
                        output = extractor.save_as_markdown(conversation, session_id)
                        print(f"✅ Saved: {output.name}")
            except (EOFError, KeyboardInterrupt):
                print("\n👋 Cancelled")
    else:
        # If other arguments are provided, run the normal CLI
        main()


if __name__ == "__main__":
    main()

# Claude Conversation Extractor

> 🚀 **High-performance desktop app for searching and analyzing Claude AI conversations** with sub-millisecond search, beautiful Flutter UI, and upcoming analytics features.

[![Zig](https://img.shields.io/badge/Zig-0.13.0-orange)](https://ziglang.org/)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue)](https://flutter.dev/)
[![SQLite FTS5](https://img.shields.io/badge/SQLite-FTS5-green)](https://www.sqlite.org/fts5.html)
[![Platform](https://img.shields.io/badge/Platform-macOS%20|%20Windows%20|%20Linux-lightgrey)](https://github.com/ZeroSumQuant/claude-conversation-extractor)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## 🎯 What is this?

Claude Conversation Extractor is a **blazing-fast desktop application** that extracts, indexes, and enables instant search across all your Claude AI conversations stored locally in `~/.claude/projects/`. 

**The Problem**: Claude stores conversations in JSONL files with no built-in search or export
**The Solution**: We index everything into SQLite FTS5 for instant full-text search with a beautiful native UI

## ✨ Key Features

### Core Features (Working Now)
- **⚡ Lightning Fast Search**: Sub-millisecond full-text search across millions of messages
- **🎨 Beautiful Desktop UI**: Native Flutter app with smooth animations and dark mode
- **📊 SQLite FTS5**: Database-backed search with BM25 ranking and snippet extraction
- **🔄 Incremental Indexing**: Only processes new messages, tracks file position
- **📁 Multiple Export Formats**: Markdown, JSON, HTML with syntax highlighting
- **🚀 Zero Dependencies**: Single binary, no runtime requirements

### Performance Metrics
| Operation | Speed | Notes |
|-----------|-------|-------|
| Search | **1.5ms** | Across 50,000+ messages |
| Import | **10,000 msg/sec** | With full indexing |
| Session Load | **21ms** | For 530MB file |
| Export | **Instant** | Direct from database |

### Coming Soon (Analytics)
- 📈 Usage analytics and time tracking
- 📊 Project identification and clustering
- 🎯 Session-based metrics (each JSONL = one session)
- 📉 Beautiful charts with Syncfusion

## 🖥️ Screenshots

### Main Search Interface
<img width="1200" alt="Claude Conversation Extractor - Search Interface" src="https://github.com/user-attachments/assets/ce4c5e66-8cf0-4e69-b1f2-67302de59e44">

### Session Browser
<img width="1200" alt="Session Browser" src="https://github.com/user-attachments/assets/f7c8f8e3-c3e0-4bcb-bd0d-b12e4c13f602">

### Conversation View
<img width="1200" alt="Conversation Display" src="https://github.com/user-attachments/assets/2f63fa23-3f09-4359-8fb3-b8e04ad88d06">

## 🚀 Quick Start

### Download Pre-built Binaries (Recommended)

**macOS** (Apple Silicon & Intel)
```bash
# Coming soon - builds being prepared
```

**Windows**
```bash
# Coming soon - builds being prepared
```

**Linux**
```bash
# Coming soon - builds being prepared
```

### Build from Source

#### Prerequisites
- [Zig 0.13.0](https://ziglang.org/download/)
- [Flutter 3.x](https://docs.flutter.dev/get-started/install)
- SQLite3 (usually pre-installed)

#### Build Instructions

```bash
# Clone the repository
git clone https://github.com/ZeroSumQuant/claude-conversation-extractor.git
cd claude-conversation-extractor

# Build the Zig backend (high performance extractor)
zig build -Doptimize=ReleaseFast

# Build the Flutter UI
cd claude_ui
flutter pub get
flutter build macos  # or windows/linux

# Run the app
open build/macos/Build/Products/Release/claude_ui.app  # macOS
# or
./build/windows/x64/runner/Release/claude_ui.exe  # Windows
# or  
./build/linux/x64/release/bundle/claude_ui  # Linux
```

## 📁 Architecture

```
┌─────────────────────────────────────────────────┐
│              Flutter UI (Dart)                  │
│        Beautiful native desktop interface       │
└─────────────────────────────────────────────────┘
                       │
                   NDJSON Protocol
                       │
┌─────────────────────────────────────────────────┐
│            Zig Backend (Core)                   │
│    Ultra-fast processing and indexing engine    │
└─────────────────────────────────────────────────┘
                       │
┌─────────────────────────────────────────────────┐
│            SQLite with FTS5                     │
│    Full-text search with BM25 ranking          │
└─────────────────────────────────────────────────┘
```

### Tech Stack
- **Backend**: Zig 0.13.0 - Systems programming for maximum performance
- **Frontend**: Flutter/Dart - Beautiful cross-platform UI
- **Database**: SQLite3 with FTS5 - Fast full-text search
- **Protocol**: NDJSON over stdin/stdout - Simple and efficient
- **State Management**: Riverpod - Reactive state management
- **Routing**: GoRouter - Declarative navigation

## 💻 Usage

### GUI Mode (Default)
Simply launch the app - it will automatically:
1. Find all Claude conversations in `~/.claude/projects/`
2. Build a search index on first run
3. Provide instant search and browsing

### CLI Mode (Advanced)
```bash
# Run the extractor directly for CLI operations
./extractor --help

# Search from command line
./extractor search "flutter widget"

# Export specific conversation
./extractor extract session_12 --format markdown

# List all sessions
./extractor list

# Build/rebuild index
./extractor index
```

## 🔍 How It Works

1. **Session Detection**: Each JSONL file represents one Claude session
2. **Incremental Import**: Only processes new messages since last import
3. **FTS5 Indexing**: Creates full-text search index with BM25 ranking
4. **Memory-Mapped Files**: Zero-copy reading for maximum performance
5. **Block Index**: O(1) line access with 256-line blocks
6. **Arena Allocators**: Efficient memory management in hot paths

## 📊 Database Schema

```sql
-- Core tables
source_files     -- Tracks JSONL files and import status
conversations    -- Conversation metadata
messages         -- All message content
messages_fts     -- FTS5 virtual table for search

-- Coming soon: Analytics tables
session_analytics     -- Per-session metrics
daily_usage          -- Aggregated daily stats
project_analytics    -- Project-level insights
```

## 🛠️ Development

### Project Structure
```
claude-conversation-extractor/
├── extractor.zig           # Zig backend (2500+ lines)
├── claude_ui/              # Flutter frontend
│   ├── lib/
│   │   ├── core/          # Backend communication
│   │   ├── features/      # App screens
│   │   ├── theme/         # Design system
│   │   └── widgets/       # Reusable components
│   └── macos/windows/linux/  # Platform code
├── docs/                   # Documentation
│   ├── ANALYTICS_IMPLEMENTATION_PLAN.md
│   └── PROJECT_RESEARCH_SUMMARY.md
└── build.zig              # Build configuration
```

### Running Tests
```bash
# Zig tests
zig build test

# Flutter tests
cd claude_ui
flutter test
```

### Performance Benchmarks
```bash
# Run performance benchmarks
./extractor benchmark

# Expected results:
# Search: <2ms for 1M messages
# Import: >10k messages/second
# Memory: <100MB for typical usage
```

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Priority Areas
- [ ] Analytics implementation (see docs/ANALYTICS_IMPLEMENTATION_PLAN.md)
- [ ] Windows/Linux platform testing
- [ ] UI/UX improvements
- [ ] Performance optimizations
- [ ] Documentation improvements

## 📝 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built with [Zig](https://ziglang.org/) for blazing performance
- UI powered by [Flutter](https://flutter.dev/)
- Search powered by [SQLite FTS5](https://www.sqlite.org/fts5.html)
- Inspired by the need to search Claude conversations efficiently

## 📧 Contact

- **GitHub Issues**: [Report bugs or request features](https://github.com/ZeroSumQuant/claude-conversation-extractor/issues)
- **Discussions**: [Join the conversation](https://github.com/ZeroSumQuant/claude-conversation-extractor/discussions)

---

**Note**: This tool is not affiliated with Anthropic or Claude. It's an independent project to help users search and analyze their locally-stored Claude conversations.
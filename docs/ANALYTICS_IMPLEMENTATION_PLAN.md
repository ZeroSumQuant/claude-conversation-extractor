# Analytics Implementation Plan

## Executive Summary

This document outlines the implementation strategy for adding comprehensive analytics to Claude Conversation Extractor, leveraging the key architectural insight that Claude Code creates one JSONL file per work session. This natural session boundary eliminates complex detection algorithms and enables straightforward, accurate usage tracking.

**Key Decisions:**
- **Charting Library**: Syncfusion Flutter Charts (commercial license required)
- **Session Detection**: Hybrid approach (file watching when active, polling when background)
- **Project Detection**: FastText embeddings for intelligent clustering
- **Architecture**: Lambda-inspired hybrid with real-time and batch layers

## Core Architecture

### Three-Layer Processing Model

```
┌─────────────────────────────────────────────────────────┐
│                    SERVING LAYER                        │
│         (Merged results, unified API, caching)          │
└─────────────────────────────────────────────────────────┘
                           ▲
        ┌──────────────────┴──────────────────┐
        │                                      │
┌───────▼────────┐                  ┌─────────▼────────┐
│  REAL-TIME     │                  │   BATCH LAYER    │
│    LAYER       │                  │                  │
│                │                  │  - Aggregations  │
│ - Active file  │                  │  - Summaries     │
│ - Live metrics │                  │  - ML processing │
│ - UI updates   │                  │  - Project ID    │
└────────────────┘                  └──────────────────┘
        ▲                                      ▲
        │                                      │
        └──────────────────┬──────────────────┘
                           │
                    JSONL FILES
              (One file = One session)
```

### Key Architectural Principles

1. **Separation of Concerns**: Analytics never impact core search performance
2. **Progressive Enhancement**: Start simple, add sophistication incrementally
3. **Privacy-First**: All processing remains local, no external dependencies
4. **Performance Preservation**: Sub-millisecond queries maintained

## Database Schema

### Core Analytics Tables

```sql
-- Session tracking with file-based identification
CREATE TABLE session_analytics (
    session_id TEXT PRIMARY KEY,        -- e.g., "session_0", "session_1"
    file_path TEXT UNIQUE NOT NULL,     -- Full path to JSONL file
    project_path TEXT,                   -- Extracted project directory
    project_id TEXT,                     -- Clustered project identifier
    start_time INTEGER NOT NULL,        -- First message timestamp (unix)
    end_time INTEGER,                    -- Last message timestamp (unix)
    duration_seconds INTEGER,            -- Total session duration
    active_seconds INTEGER,              -- Active time (excluding gaps > 5min)
    message_count INTEGER DEFAULT 0,
    user_message_count INTEGER DEFAULT 0,
    assistant_message_count INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT FALSE,    -- Currently being written to
    last_byte_processed INTEGER DEFAULT 0,
    file_size INTEGER,
    created_at INTEGER DEFAULT (unixepoch()),
    updated_at INTEGER DEFAULT (unixepoch())
);

-- Real-time events for active session
CREATE TABLE analytics_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    event_type TEXT NOT NULL,           -- 'message', 'pause', 'resume', 'end'
    metadata JSON,
    FOREIGN KEY (session_id) REFERENCES session_analytics(session_id)
);

-- Pre-computed daily aggregations
CREATE TABLE daily_usage (
    date TEXT PRIMARY KEY,               -- YYYY-MM-DD format
    total_sessions INTEGER DEFAULT 0,
    total_hours REAL DEFAULT 0,
    active_hours REAL DEFAULT 0,        -- Excluding idle time
    total_messages INTEGER DEFAULT 0,
    user_messages INTEGER DEFAULT 0,
    assistant_messages INTEGER DEFAULT 0,
    unique_projects INTEGER DEFAULT 0,
    longest_session_hours REAL DEFAULT 0,
    updated_at INTEGER DEFAULT (unixepoch())
);

-- Weekly rollups for performance
CREATE TABLE weekly_usage (
    week_start TEXT PRIMARY KEY,        -- Monday of week (YYYY-MM-DD)
    year_week TEXT NOT NULL,            -- YYYY-WW format
    total_sessions INTEGER DEFAULT 0,
    total_hours REAL DEFAULT 0,
    active_hours REAL DEFAULT 0,
    total_messages INTEGER DEFAULT 0,
    avg_daily_hours REAL DEFAULT 0,
    unique_projects INTEGER DEFAULT 0,
    updated_at INTEGER DEFAULT (unixepoch())
);

-- Monthly rollups
CREATE TABLE monthly_usage (
    month TEXT PRIMARY KEY,             -- YYYY-MM format
    total_sessions INTEGER DEFAULT 0,
    total_hours REAL DEFAULT 0,
    active_hours REAL DEFAULT 0,
    total_messages INTEGER DEFAULT 0,
    avg_daily_hours REAL DEFAULT 0,
    unique_projects INTEGER DEFAULT 0,
    updated_at INTEGER DEFAULT (unixepoch())
);

-- Project-level analytics
CREATE TABLE project_analytics (
    project_id TEXT PRIMARY KEY,
    project_name TEXT,                  -- Extracted or inferred name
    project_path TEXT,                  -- Common path prefix
    first_seen INTEGER NOT NULL,
    last_seen INTEGER NOT NULL,
    total_sessions INTEGER DEFAULT 0,
    total_hours REAL DEFAULT 0,
    total_messages INTEGER DEFAULT 0,
    file_patterns JSON,                 -- Common file extensions/patterns
    technologies JSON,                  -- Detected tech stack
    confidence_score REAL DEFAULT 0.0,  -- Project detection confidence
    updated_at INTEGER DEFAULT (unixepoch())
);

-- Performance indexes
CREATE INDEX idx_session_active ON session_analytics(is_active, updated_at DESC);
CREATE INDEX idx_session_project ON session_analytics(project_id, start_time DESC);
CREATE INDEX idx_events_session ON analytics_events(session_id, timestamp DESC);
CREATE INDEX idx_daily_date ON daily_usage(date DESC);
CREATE INDEX idx_project_last_seen ON project_analytics(last_seen DESC);

-- Triggers for automatic aggregation
CREATE TRIGGER update_session_timestamp 
AFTER UPDATE ON session_analytics
BEGIN
    UPDATE session_analytics SET updated_at = unixepoch() WHERE session_id = NEW.session_id;
END;
```

## Implementation Phases

### Phase 1: Foundation (Week 1)

#### 1.1 Database Setup
- [ ] Create analytics schema in SQLite
- [ ] Add migration support for schema updates
- [ ] Implement connection pooling for analytics queries
- [ ] Add analytics tables to existing database initialization

#### 1.2 Session Detection Infrastructure
- [ ] Implement session file identification from JSONL paths
- [ ] Create session_id mapping (session_0, session_1, etc.)
- [ ] Add session tracking to existing import pipeline
- [ ] Calculate basic session metrics (start, end, duration)

#### 1.3 Protocol Extensions
```zig
// Add to protocol handlers in extractor.zig
fn protocolGetAnalytics(allocator: std.mem.Allocator, db: *Database, params: ?std.json.Value) !void {
    const time_range = params.?.object.get("range").?.string; // "today", "week", "month", "all"
    const group_by = params.?.object.get("groupBy").?.string; // "day", "week", "month"
    
    // Query appropriate aggregation table based on parameters
    const analytics = try queryAnalytics(db, time_range, group_by);
    try sendResult(allocator, analytics);
}

fn protocolGetActiveSession(allocator: std.mem.Allocator, db: *Database) !void {
    const active = try db.queryRow(
        "SELECT * FROM session_analytics WHERE is_active = TRUE LIMIT 1"
    );
    try sendResult(allocator, active);
}
```

### Phase 2: Active Session Monitoring (Week 2)

#### 2.1 Hybrid Monitoring System
```zig
const SessionMonitor = struct {
    mode: enum { Active, Background },
    watcher: ?FileWatcher = null,
    poll_timer: ?Timer = null,
    current_session_file: []const u8,
    last_size: u64 = 0,
    last_activity: i64 = 0,
    
    pub fn init(allocator: std.mem.Allocator) !SessionMonitor {
        // Initialize based on platform capabilities
        if (builtin.os.tag == .macos) {
            return .{
                .mode = .Active,
                .watcher = try FileWatcher.initFSEvents(allocator),
            };
        } else {
            return .{
                .mode = .Background,
                .poll_timer = try Timer.init(5000), // 5 second polling
            };
        }
    }
    
    pub fn switchMode(self: *SessionMonitor, mode: @TypeOf(self.mode)) !void {
        if (mode == .Active and self.watcher == null) {
            // Switch to file watching
            self.poll_timer.?.deinit();
            self.poll_timer = null;
            self.watcher = try FileWatcher.init();
        } else if (mode == .Background and self.poll_timer == null) {
            // Switch to polling
            self.watcher.?.deinit();
            self.watcher = null;
            self.poll_timer = try Timer.init(5000);
        }
        self.mode = mode;
    }
    
    pub fn checkForUpdates(self: *SessionMonitor) !SessionUpdate {
        const current_time = std.time.milliTimestamp();
        
        if (self.mode == .Active) {
            // Use file watcher events
            if (try self.watcher.?.hasChanges()) {
                const new_size = try getFileSize(self.current_session_file);
                if (new_size > self.last_size) {
                    self.last_size = new_size;
                    self.last_activity = current_time;
                    return .{ .active = true, .bytes_added = new_size - self.last_size };
                }
            }
        } else {
            // Use adaptive polling
            const stat = try std.fs.cwd().statFile(self.current_session_file);
            if (stat.size > self.last_size) {
                self.last_size = stat.size;
                self.last_activity = current_time;
                // Decrease poll interval when active
                self.poll_timer.?.setInterval(1000);
                return .{ .active = true, .bytes_added = stat.size - self.last_size };
            } else if (current_time - self.last_activity > 300000) { // 5 min idle
                // Increase poll interval when idle
                self.poll_timer.?.setInterval(30000);
                return .{ .active = false, .idle_minutes = 5 };
            }
        }
        
        return .{ .active = false, .idle_minutes = 0 };
    }
};
```

#### 2.2 Real-time UI Updates
```dart
// In Flutter (zig_core_client.dart)
Stream<SessionMetrics> watchActiveSession() {
  return _eventController.stream.where((event) => event.type == 'session_update')
    .map((event) => SessionMetrics.fromJson(event.data));
}

// In analytics screen
StreamBuilder<SessionMetrics>(
  stream: ref.watch(zigCoreProvider.notifier).watchActiveSession(),
  builder: (context, snapshot) {
    if (snapshot.hasData) {
      return ActiveSessionCard(
        duration: snapshot.data!.duration,
        messageCount: snapshot.data!.messageCount,
        isActive: snapshot.data!.isActive,
      );
    }
    return const Text('No active session');
  },
);
```

### Phase 3: Project Identification with FastText (Week 3)

#### 3.1 FastText Integration
```zig
const FastText = struct {
    model: *c.fasttext_model,
    
    pub fn loadModel(path: []const u8) !FastText {
        const model = c.fasttext_load_model(path.ptr) orelse return error.ModelLoadFailed;
        return .{ .model = model };
    }
    
    pub fn getVector(self: *FastText, text: []const u8) ![300]f32 {
        var vector: [300]f32 = undefined;
        c.fasttext_get_sentence_vector(self.model, text.ptr, &vector);
        return vector;
    }
    
    pub fn findSimilarProjects(self: *FastText, path: []const u8, threshold: f32) ![]const u8 {
        const vector = try self.getVector(path);
        // Query existing project vectors from database
        // Return most similar project_id if similarity > threshold
        // Otherwise create new project_id
    }
};
```

#### 3.2 Project Clustering Pipeline
```zig
fn identifyProject(db: *Database, file_path: []const u8) ![]const u8 {
    // Step 1: Extract project markers
    const markers = try extractProjectMarkers(file_path);
    // Look for: package.json, .git, Cargo.toml, go.mod, etc.
    
    // Step 2: Get path components
    const path_parts = try splitPath(file_path);
    const project_root = try findProjectRoot(path_parts, markers);
    
    // Step 3: Generate embedding using FastText
    const embedding = try fasttext.getVector(project_root);
    
    // Step 4: Find or create project
    const existing = try db.queryRow(
        "SELECT project_id FROM project_analytics WHERE vector_distance(embedding, ?) < 0.3",
        .{embedding}
    );
    
    if (existing) |proj| {
        return proj.project_id;
    } else {
        // Create new project
        const new_id = try generateProjectId();
        try db.exec(
            "INSERT INTO project_analytics (project_id, project_path, embedding) VALUES (?, ?, ?)",
            .{new_id, project_root, embedding}
        );
        return new_id;
    }
}
```

### Phase 4: Syncfusion Charts Integration (Week 4)

#### 4.1 Chart Components
```dart
// lib/features/analytics/widgets/usage_chart.dart
import 'package:syncfusion_flutter_charts/charts.dart';

class UsageChart extends ConsumerWidget {
  final TimeRange range;
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analytics = ref.watch(analyticsProvider(range));
    
    return analytics.when(
      data: (data) => SfCartesianChart(
        primaryXAxis: DateTimeAxis(
          intervalType: range == TimeRange.day 
            ? DateTimeIntervalType.hours 
            : DateTimeIntervalType.days,
        ),
        primaryYAxis: NumericAxis(
          title: AxisTitle(text: 'Hours'),
        ),
        series: <ChartSeries>[
          FastLineSeries<UsagePoint, DateTime>(
            dataSource: data.points,
            xValueMapper: (point, _) => point.timestamp,
            yValueMapper: (point, _) => point.hours,
            color: Theme.of(context).colorScheme.primary,
            animationDuration: 500,
          ),
        ],
        tooltipBehavior: TooltipBehavior(enable: true),
        zoomPanBehavior: ZoomPanBehavior(
          enablePanning: true,
          enableDoubleTapZooming: true,
          enablePinching: true,
        ),
      ),
      loading: () => const CircularProgressIndicator(),
      error: (err, stack) => Text('Error: $err'),
    );
  }
}
```

#### 4.2 Real-time Updates
```dart
class LiveSessionIndicator extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeSession = ref.watch(activeSessionProvider);
    
    return activeSession.when(
      data: (session) {
        if (session == null) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No active session'),
            ),
          );
        }
        
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('Active Session'),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _formatDuration(session.duration),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text('${session.messageCount} messages'),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: null, // Indeterminate while active
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const CircularProgressIndicator(),
      error: (err, _) => Text('Error: $err'),
    );
  }
  
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:'
           '${minutes.toString().padLeft(2, '0')}:'
           '${seconds.toString().padLeft(2, '0')}';
  }
}
```

### Phase 5: Batch Processing & Aggregation (Week 5)

#### 5.1 Background Worker
```zig
const BatchProcessor = struct {
    db: *Database,
    arena: std.heap.ArenaAllocator,
    last_run: i64 = 0,
    
    pub fn processCompletedSessions(self: *BatchProcessor) !void {
        defer self.arena.deinit();
        
        // Find sessions that are complete but not fully processed
        const unprocessed = try self.db.query(
            \\SELECT session_id, file_path 
            \\FROM session_analytics 
            \\WHERE is_active = FALSE 
            \\  AND last_byte_processed < file_size
            \\ORDER BY end_time DESC
            \\LIMIT 10
        );
        
        for (unprocessed) |session| {
            try self.processSession(session);
            try self.updateAggregations(session);
        }
        
        self.last_run = std.time.milliTimestamp();
    }
    
    fn updateAggregations(self: *BatchProcessor, session: Session) !void {
        // Update daily aggregation
        try self.db.exec(
            \\INSERT INTO daily_usage (date, total_sessions, total_hours, total_messages)
            \\VALUES (DATE(?), 1, ?, ?)
            \\ON CONFLICT(date) DO UPDATE SET
            \\  total_sessions = total_sessions + 1,
            \\  total_hours = total_hours + excluded.total_hours,
            \\  total_messages = total_messages + excluded.total_messages
            ,
            .{session.start_time, session.duration_hours, session.message_count}
        );
        
        // Update weekly aggregation
        const week_start = getWeekStart(session.start_time);
        try self.db.exec(
            \\INSERT INTO weekly_usage (week_start, year_week, total_sessions, total_hours)
            \\VALUES (?, strftime('%Y-%W', ?), 1, ?)
            \\ON CONFLICT(week_start) DO UPDATE SET
            \\  total_sessions = total_sessions + 1,
            \\  total_hours = total_hours + excluded.total_hours
            ,
            .{week_start, session.start_time, session.duration_hours}
        );
    }
};
```

## Performance Optimizations

### 1. Incremental Processing
- Only process new data since last_byte_processed
- Use BlockIndex for O(1) line access
- Batch inserts with prepared statements

### 2. Smart Caching
```zig
const AnalyticsCache = struct {
    daily: std.AutoHashMap([]const u8, DailyMetrics),
    weekly: std.AutoHashMap([]const u8, WeeklyMetrics),
    ttl_seconds: i64 = 300, // 5 minute cache
    
    pub fn get(self: *AnalyticsCache, key: []const u8) ?DailyMetrics {
        if (self.daily.get(key)) |entry| {
            if (std.time.milliTimestamp() - entry.cached_at < self.ttl_seconds * 1000) {
                return entry.metrics;
            }
            // Expired, remove from cache
            _ = self.daily.remove(key);
        }
        return null;
    }
};
```

### 3. Query Optimization
- Use covering indexes for all analytics queries
- Partition tables by date for faster aggregations
- Maintain materialized views for complex queries

## UI/UX Implementation

### Analytics Dashboard Layout
```
┌─────────────────────────────────────────────────────────┐
│  Active Session Card                                    │
│  [●] Currently working - 01:23:45 - 42 messages        │
└─────────────────────────────────────────────────────────┘

┌─────────────────┬────────────────┬──────────────────────┐
│  Today's Stats  │  This Week     │  This Month          │
│  3 sessions     │  18 sessions   │  72 sessions         │
│  5.2 hours      │  28.5 hours    │  112.3 hours         │
│  234 messages   │  1,523 msgs    │  6,234 messages      │
└─────────────────┴────────────────┴──────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  Usage Over Time (Interactive Syncfusion Chart)         │
│  [Chart with zoom, pan, tooltips]                       │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  Projects (Clustered by FastText)                       │
│  • claude-extractor     45.2 hrs  ████████████         │
│  • bit-trader          23.1 hrs  ██████                │
│  • flutter-app         12.5 hrs  ███                   │
└─────────────────────────────────────────────────────────┘
```

### Interactive Features
1. **Hover Details**: Show session details on hover
2. **Click to Drill Down**: Click project to see sessions
3. **Time Range Selector**: Day/Week/Month/Year/All
4. **Export Options**: CSV, JSON, PDF reports
5. **Live Updates**: Real-time counter for active session

## Testing Strategy

### Unit Tests
```zig
test "session duration calculation" {
    const session = Session{
        .start_time = 1700000000,
        .end_time = 1700003600,
    };
    try testing.expectEqual(@as(f32, 1.0), session.getDurationHours());
}

test "active time calculation excludes gaps" {
    const messages = [_]Message{
        .{ .timestamp = 1700000000 }, // 0:00
        .{ .timestamp = 1700000060 }, // 0:01
        .{ .timestamp = 1700000400 }, // 0:06:40 (5:40 gap)
        .{ .timestamp = 1700000460 }, // 0:07:40
    };
    const active_time = calculateActiveTime(messages, 300); // 5 min gap threshold
    try testing.expectEqual(@as(i64, 120), active_time); // 2 minutes active
}
```

### Integration Tests
- Test file watching with mock JSONL updates
- Verify aggregation triggers update correctly
- Test cache invalidation on new data
- Verify UI updates with streaming events

### Performance Benchmarks
- Analytics query must complete in <100ms
- Dashboard load time <500ms
- Real-time updates <50ms latency
- Batch processing 10,000 messages/second

## Deployment & Migration

### Database Migration
```sql
-- Migration 001: Add analytics tables
BEGIN TRANSACTION;

-- Create tables (as defined above)
CREATE TABLE IF NOT EXISTS session_analytics ...;
CREATE TABLE IF NOT EXISTS daily_usage ...;

-- Migrate existing data
INSERT INTO session_analytics (session_id, file_path, start_time, end_time, message_count)
SELECT 
    'session_' || ROW_NUMBER() OVER (ORDER BY MIN(timestamp)),
    conversation_id,
    MIN(timestamp),
    MAX(timestamp),
    COUNT(*)
FROM messages
GROUP BY conversation_id;

-- Create indexes
CREATE INDEX ...;

COMMIT;
```

### Rollout Strategy
1. **Alpha**: Enable for development builds only
2. **Beta**: Add feature flag for opt-in users
3. **GA**: Enable by default with opt-out option

## Privacy & Security

### Data Handling
- All analytics data remains local
- No network requests for analytics
- Encrypted at rest using OS keychain
- User can delete analytics data anytime

### Compliance
- GDPR compliant (local processing only)
- No PII in analytics tables
- Configurable retention policies
- Export and deletion tools provided

## Success Metrics

### Technical Metrics
- Query performance maintained (<100ms p99)
- Dashboard renders at 60fps
- Zero impact on core search functionality
- <1% CPU usage for monitoring

### User Metrics
- Analytics tab engagement rate
- Feature retention after 30 days
- User-reported insights gained
- Support ticket reduction

## Timeline

| Week | Phase | Deliverables |
|------|-------|-------------|
| 1 | Foundation | Database schema, basic session tracking |
| 2 | Monitoring | Active session detection, real-time updates |
| 3 | Project ID | FastText integration, clustering |
| 4 | UI | Syncfusion charts, analytics dashboard |
| 5 | Polish | Batch processing, optimizations, testing |

## Conclusion

This implementation plan leverages Claude Code's elegant file-per-session architecture to deliver powerful analytics with minimal complexity. By combining Zig's performance with Flutter's rich UI capabilities and Syncfusion's professional charting, we can provide users with deep insights into their Claude Code usage patterns while maintaining the application's core values of speed, privacy, and simplicity.
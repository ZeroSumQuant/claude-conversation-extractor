#!/usr/bin/env python3
"""
Conversation statistics and analytics for Claude Conversation Extractor.

Provides detailed analytics about conversations including:
- Message counts and distributions
- Token/word estimates
- Time-based analysis
- Most active periods
- Conversation patterns
"""

import json
import re
from collections import Counter, defaultdict
from dataclasses import dataclass, asdict
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any

# Constants for analysis
AVERAGE_CHARS_PER_TOKEN = 4  # Rough estimate for token counting
WORDS_PER_MINUTE_READING = 200  # Average reading speed


@dataclass
class ConversationStats:
    """Statistics for a single conversation"""
    
    session_id: str
    total_messages: int
    user_messages: int
    assistant_messages: int
    total_words: int
    total_chars: int
    estimated_tokens: int
    estimated_reading_time_minutes: float
    start_time: Optional[datetime]
    end_time: Optional[datetime]
    duration: Optional[timedelta]
    average_message_length: float
    longest_message: int
    shortest_message: int
    messages_per_hour: float
    
    def to_dict(self) -> Dict:
        """Convert to dictionary for JSON serialization"""
        data = asdict(self)
        # Convert datetime objects to strings
        if self.start_time:
            data['start_time'] = self.start_time.isoformat()
        if self.end_time:
            data['end_time'] = self.end_time.isoformat()
        if self.duration:
            data['duration'] = str(self.duration)
        return data


@dataclass
class AggregateStats:
    """Aggregate statistics across multiple conversations"""
    
    total_conversations: int
    total_messages: int
    total_user_messages: int
    total_assistant_messages: int
    total_words: int
    total_chars: int
    estimated_total_tokens: int
    estimated_total_reading_hours: float
    most_active_day: Optional[str]
    most_active_hour: Optional[int]
    average_conversation_length: float
    longest_conversation: Tuple[str, int]  # (session_id, message_count)
    shortest_conversation: Tuple[str, int]
    date_range: Tuple[Optional[datetime], Optional[datetime]]
    daily_message_counts: Dict[str, int]
    hourly_distribution: Dict[int, int]
    common_topics: List[Tuple[str, int]]  # Top topics/keywords
    
    def to_dict(self) -> Dict:
        """Convert to dictionary for JSON serialization"""
        data = asdict(self)
        # Convert datetime objects
        if self.date_range[0]:
            data['date_range'] = [
                self.date_range[0].isoformat() if self.date_range[0] else None,
                self.date_range[1].isoformat() if self.date_range[1] else None
            ]
        return data


class ConversationAnalyzer:
    """Analyze Claude conversations for statistics and patterns"""
    
    def __init__(self):
        """Initialize the analyzer"""
        self.stop_words = {
            'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
            'is', 'are', 'was', 'were', 'be', 'been', 'being', 'have', 'has', 'had',
            'do', 'does', 'did', 'will', 'would', 'could', 'should', 'may', 'might',
            'i', 'you', 'we', 'they', 'it', 'this', 'that', 'these', 'those',
            'with', 'from', 'up', 'down', 'out', 'off', 'over', 'under', 'again',
            'can', 'just', 'now', 'then', 'also', 'very', 'here', 'there', 'where'
        }
    
    def analyze_conversation(self, conversation: List[Dict[str, Any]], 
                            session_id: str) -> ConversationStats:
        """
        Analyze a single conversation for statistics.
        
        Args:
            conversation: List of message dictionaries
            session_id: Session identifier
            
        Returns:
            ConversationStats object with analysis results
        """
        if not conversation:
            return self._empty_stats(session_id)
        
        # Count messages by role
        user_messages = sum(1 for msg in conversation if msg.get('role') == 'user')
        assistant_messages = sum(1 for msg in conversation if msg.get('role') == 'assistant')
        
        # Text analysis
        total_words = 0
        total_chars = 0
        message_lengths = []
        
        for msg in conversation:
            content = msg.get('content', '')
            if isinstance(content, str):
                words = len(content.split())
                chars = len(content)
                total_words += words
                total_chars += chars
                message_lengths.append(chars)
        
        # Time analysis
        start_time = None
        end_time = None
        
        for msg in conversation:
            timestamp_str = msg.get('timestamp')
            if timestamp_str:
                try:
                    timestamp = datetime.fromisoformat(
                        timestamp_str.replace('Z', '+00:00')
                    )
                    if not start_time or timestamp < start_time:
                        start_time = timestamp
                    if not end_time or timestamp > end_time:
                        end_time = timestamp
                except (ValueError, TypeError):
                    pass
        
        # Calculate derived metrics
        duration = None
        messages_per_hour = 0
        
        if start_time and end_time:
            duration = end_time - start_time
            if duration.total_seconds() > 0:
                hours = duration.total_seconds() / 3600
                messages_per_hour = len(conversation) / hours if hours > 0 else 0
        
        # Calculate averages and extremes
        avg_length = sum(message_lengths) / len(message_lengths) if message_lengths else 0
        longest = max(message_lengths) if message_lengths else 0
        shortest = min(message_lengths) if message_lengths else 0
        
        # Estimates
        estimated_tokens = total_chars // AVERAGE_CHARS_PER_TOKEN
        reading_time = total_words / WORDS_PER_MINUTE_READING
        
        return ConversationStats(
            session_id=session_id,
            total_messages=len(conversation),
            user_messages=user_messages,
            assistant_messages=assistant_messages,
            total_words=total_words,
            total_chars=total_chars,
            estimated_tokens=estimated_tokens,
            estimated_reading_time_minutes=reading_time,
            start_time=start_time,
            end_time=end_time,
            duration=duration,
            average_message_length=avg_length,
            longest_message=longest,
            shortest_message=shortest,
            messages_per_hour=messages_per_hour
        )
    
    def analyze_multiple(self, conversations: List[Tuple[List[Dict], str]]) -> AggregateStats:
        """
        Analyze multiple conversations for aggregate statistics.
        
        Args:
            conversations: List of (conversation, session_id) tuples
            
        Returns:
            AggregateStats object with analysis results
        """
        if not conversations:
            return self._empty_aggregate_stats()
        
        # Analyze each conversation
        all_stats = []
        for conversation, session_id in conversations:
            stats = self.analyze_conversation(conversation, session_id)
            all_stats.append(stats)
        
        # Aggregate metrics
        total_messages = sum(s.total_messages for s in all_stats)
        total_user = sum(s.user_messages for s in all_stats)
        total_assistant = sum(s.assistant_messages for s in all_stats)
        total_words = sum(s.total_words for s in all_stats)
        total_chars = sum(s.total_chars for s in all_stats)
        total_tokens = sum(s.estimated_tokens for s in all_stats)
        total_reading_hours = sum(s.estimated_reading_time_minutes for s in all_stats) / 60
        
        # Find extremes
        longest = max(all_stats, key=lambda s: s.total_messages)
        shortest = min(all_stats, key=lambda s: s.total_messages)
        
        # Date range
        all_starts = [s.start_time for s in all_stats if s.start_time]
        all_ends = [s.end_time for s in all_stats if s.end_time]
        
        date_range = (
            min(all_starts) if all_starts else None,
            max(all_ends) if all_ends else None
        )
        
        # Time-based analysis
        daily_counts = defaultdict(int)
        hourly_counts = defaultdict(int)
        
        for conv, _ in conversations:
            for msg in conv:
                timestamp_str = msg.get('timestamp')
                if timestamp_str:
                    try:
                        timestamp = datetime.fromisoformat(
                            timestamp_str.replace('Z', '+00:00')
                        )
                        daily_counts[timestamp.date().isoformat()] += 1
                        hourly_counts[timestamp.hour] += 1
                    except (ValueError, TypeError):
                        pass
        
        # Find most active periods
        most_active_day = max(daily_counts.items(), key=lambda x: x[1])[0] if daily_counts else None
        most_active_hour = max(hourly_counts.items(), key=lambda x: x[1])[0] if hourly_counts else None
        
        # Extract common topics
        topics = self._extract_topics(conversations)
        
        return AggregateStats(
            total_conversations=len(conversations),
            total_messages=total_messages,
            total_user_messages=total_user,
            total_assistant_messages=total_assistant,
            total_words=total_words,
            total_chars=total_chars,
            estimated_total_tokens=total_tokens,
            estimated_total_reading_hours=total_reading_hours,
            most_active_day=most_active_day,
            most_active_hour=most_active_hour,
            average_conversation_length=total_messages / len(conversations),
            longest_conversation=(longest.session_id, longest.total_messages),
            shortest_conversation=(shortest.session_id, shortest.total_messages),
            date_range=date_range,
            daily_message_counts=dict(daily_counts),
            hourly_distribution=dict(hourly_counts),
            common_topics=topics[:10]  # Top 10 topics
        )
    
    def _extract_topics(self, conversations: List[Tuple[List[Dict], str]], 
                       min_length: int = 4) -> List[Tuple[str, int]]:
        """
        Extract common topics/keywords from conversations.
        
        Args:
            conversations: List of conversations
            min_length: Minimum word length to consider
            
        Returns:
            List of (topic, count) tuples sorted by frequency
        """
        word_counter = Counter()
        
        for conversation, _ in conversations:
            for msg in conversation:
                content = msg.get('content', '')
                if isinstance(content, str):
                    # Extract words (alphanumeric only)
                    words = re.findall(r'\b[a-zA-Z]+\b', content.lower())
                    
                    # Filter words
                    for word in words:
                        if (len(word) >= min_length and 
                            word not in self.stop_words and
                            not word.isdigit()):
                            word_counter[word] += 1
        
        return word_counter.most_common(20)
    
    def _empty_stats(self, session_id: str) -> ConversationStats:
        """Return empty statistics for a conversation"""
        return ConversationStats(
            session_id=session_id,
            total_messages=0,
            user_messages=0,
            assistant_messages=0,
            total_words=0,
            total_chars=0,
            estimated_tokens=0,
            estimated_reading_time_minutes=0,
            start_time=None,
            end_time=None,
            duration=None,
            average_message_length=0,
            longest_message=0,
            shortest_message=0,
            messages_per_hour=0
        )
    
    def _empty_aggregate_stats(self) -> AggregateStats:
        """Return empty aggregate statistics"""
        return AggregateStats(
            total_conversations=0,
            total_messages=0,
            total_user_messages=0,
            total_assistant_messages=0,
            total_words=0,
            total_chars=0,
            estimated_total_tokens=0,
            estimated_total_reading_hours=0,
            most_active_day=None,
            most_active_hour=None,
            average_conversation_length=0,
            longest_conversation=("", 0),
            shortest_conversation=("", 0),
            date_range=(None, None),
            daily_message_counts={},
            hourly_distribution={},
            common_topics=[]
        )
    
    def generate_report(self, stats: ConversationStats) -> str:
        """
        Generate a human-readable report from statistics.
        
        Args:
            stats: ConversationStats object
            
        Returns:
            Formatted report string
        """
        report = []
        report.append("📊 Conversation Statistics")
        report.append("=" * 50)
        report.append(f"Session: {stats.session_id[:8]}...")
        report.append(f"Total Messages: {stats.total_messages}")
        report.append(f"  - User: {stats.user_messages}")
        report.append(f"  - Assistant: {stats.assistant_messages}")
        report.append(f"\nText Analysis:")
        report.append(f"  - Total Words: {stats.total_words:,}")
        report.append(f"  - Total Characters: {stats.total_chars:,}")
        report.append(f"  - Estimated Tokens: {stats.estimated_tokens:,}")
        report.append(f"  - Reading Time: {stats.estimated_reading_time_minutes:.1f} minutes")
        
        if stats.start_time and stats.end_time:
            report.append(f"\nTime Analysis:")
            report.append(f"  - Start: {stats.start_time.strftime('%Y-%m-%d %H:%M')}")
            report.append(f"  - End: {stats.end_time.strftime('%Y-%m-%d %H:%M')}")
            if stats.duration:
                report.append(f"  - Duration: {stats.duration}")
                report.append(f"  - Messages/Hour: {stats.messages_per_hour:.1f}")
        
        report.append(f"\nMessage Lengths:")
        report.append(f"  - Average: {stats.average_message_length:.0f} chars")
        report.append(f"  - Longest: {stats.longest_message:,} chars")
        report.append(f"  - Shortest: {stats.shortest_message} chars")
        
        return "\n".join(report)
    
    def save_stats(self, stats: ConversationStats, output_path: Path):
        """Save statistics to JSON file"""
        with open(output_path, 'w') as f:
            json.dump(stats.to_dict(), f, indent=2)
    
    def save_aggregate_stats(self, stats: AggregateStats, output_path: Path):
        """Save aggregate statistics to JSON file"""
        with open(output_path, 'w') as f:
            json.dump(stats.to_dict(), f, indent=2)


# Testing
if __name__ == "__main__":
    # Test with sample data
    test_conversation = [
        {
            "role": "user",
            "content": "Hello Claude, can you help me with Python programming?",
            "timestamp": "2024-01-15T10:00:00Z"
        },
        {
            "role": "assistant",
            "content": "Of course! I'd be happy to help you with Python programming. What specific topic or problem would you like to work on?",
            "timestamp": "2024-01-15T10:00:30Z"
        },
        {
            "role": "user",
            "content": "I need to understand decorators better.",
            "timestamp": "2024-01-15T10:01:00Z"
        },
        {
            "role": "assistant",
            "content": "Decorators in Python are a powerful feature that allow you to modify or enhance functions and classes. Let me explain with examples...",
            "timestamp": "2024-01-15T10:01:30Z"
        }
    ]
    
    analyzer = ConversationAnalyzer()
    stats = analyzer.analyze_conversation(test_conversation, "test123")
    print(analyzer.generate_report(stats))
    
    # Test aggregate stats
    conversations = [(test_conversation, "test123"), (test_conversation, "test456")]
    agg_stats = analyzer.analyze_multiple(conversations)
    print(f"\n\nAggregate Stats:")
    print(f"Total Conversations: {agg_stats.total_conversations}")
    print(f"Total Messages: {agg_stats.total_messages}")
    print(f"Common Topics: {agg_stats.common_topics[:5]}")
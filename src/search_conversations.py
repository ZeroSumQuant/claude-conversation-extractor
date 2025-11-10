#!/usr/bin/env python3
"""
Search functionality for Claude Conversation Extractor

This module provides powerful search capabilities including:
- Full-text search with relevance ranking
- Regex pattern matching
- Date range filtering
- Speaker filtering (Human/Assistant)
- Semantic search using NLP

Adapted from CAKE's conversation parser for Claude conversation search.
"""

import json
import re
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Set

# Optional NLP imports for semantic search
try:
    import spacy

    SPACY_AVAILABLE = True
except ImportError:
    SPACY_AVAILABLE = False
    print("Note: Install spacy for enhanced semantic search capabilities")
    print("      pip install spacy && python -m spacy download en_core_web_sm")


# Constants
MAJOR_SEPARATOR_WIDTH = 60
DEFAULT_MAX_RESULTS = 20
MAX_CONTENT_LENGTH = 200
DEFAULT_CONTEXT_SIZE  = 150
DEFAULT_MAX_TOPICS = 5
CONTENT_LENGTH_PROCESSING = 10
MAX_NOUN_PHRASES_LENGTH = 3
INDENT_NUMBER = 2
MIN_TOPIC_PHRASE_COUNT = 1

# Other constants for relevance or similarity
RELEVANCE_THRESHOLD = 0.1
MIN_RELEVANCE_COMPARED = 1.0
MATCH_FACTOR_FOR_RELEVANCE = 0.2
MATCH_BONUS = 0.5
MIN_RELEVANCE_MULTIPLE_OCCURRENCES = 0.3
MATCH_FACTOR_MULTIPLE_OCCURRENCES = 0.1
MIN_RELEVANCE_OVERLAP = 0.4
MATCH_FACTOR_OVERLAP = 0.4
PROXIMITY_BONUS = 0.1
MIN_TOKENS_FOR_PROXIMITY_BONUS = 1
PROXIMITY_WINDOW_MULTIPLIER = 2
ADDITIONAL_BOOST_EXACT_MATCH = 0.3
MATCH_CONTEXT_STEP = 100
SEMANTIC_SIMILARITY_THRESHOLD = 0.3
CONTEXT_FALLBACK_MULTIPLIER = 2


@dataclass
class SearchResult:
    """Represents a search result with context"""

    file_path: Path
    conversation_id: str
    matched_content: str
    context: str  # Surrounding text for context
    speaker: str  # 'human' or 'assistant'
    timestamp: Optional[datetime] = None
    relevance_score: float = 0.0
    line_number: int = 0

    def __str__(self) -> str:
        """User-friendly string representation"""
        return (
            f"\n{'=' * MAJOR_SEPARATOR_WIDTH}\n"
            f"File: {self.file_path.name}\n"
            f"Speaker: {self.speaker.title()}\n"
            f"Relevance: {self.relevance_score:.0%}\n"
            f"{'=' * MAJOR_SEPARATOR_WIDTH}\n"
            f"{self.context}\n"
        )


class ConversationSearcher:
    """
    Main search engine for Claude conversations.

    Provides multiple search modes and intelligent ranking.
    """

    def __init__(self, cache_dir: Optional[Path] = None):
        """
        Initialize the searcher.

        Args:
            cache_dir: Optional directory for caching processed conversations
        """
        self.cache_dir = cache_dir or Path.home() / ".claude" / ".search_cache"
        self.cache_dir.mkdir(parents=True, exist_ok=True)

        # Initialize NLP if available
        self.nlp = None
        if SPACY_AVAILABLE:
            try:
                self.nlp = spacy.load("en_core_web_sm")
                # Disable unnecessary components for speed
                self.nlp.select_pipes(disable=["ner", "lemmatizer"])
            except Exception:
                print("Warning: spaCy model not found. Using basic search.")

        # Common words to ignore in relevance scoring
        self.stop_words = {
            "the",
            "a",
            "an",
            "and",
            "or",
            "but",
            "in",
            "on",
            "at",
            "to",
            "for",
            "is",
            "are",
            "was",
            "were",
            "be",
            "been",
            "being",
            "have",
            "has",
            "had",
            "do",
            "does",
            "did",
            "will",
            "would",
            "could",
            "should",
            "may",
            "might",
            "i",
            "you",
            "we",
            "they",
            "it",
            "this",
            "that",
            "these",
            "those",
        }

    def search(
        self,
        query: str,
        search_dir: Optional[Path] = None,
        mode: str = "smart",
        date_from: Optional[datetime] = None,
        date_to: Optional[datetime] = None,
        speaker_filter: Optional[str] = None,
        max_results: int = DEFAULT_MAX_RESULTS,
        case_sensitive: bool = False,
    ) -> List[SearchResult]:
        """
        Search conversations with various filters.

        Args:
            query: Search query (text or regex pattern)
            search_dir: Directory to search in (default: ~/.claude/projects)
            mode: Search mode - "smart", "exact", "regex", "semantic"
            date_from: Filter results from this date
            date_to: Filter results until this date
            speaker_filter: Filter by speaker - "human", "assistant", or None for both
            max_results: Maximum number of results to return
            case_sensitive: Whether search should be case-sensitive

        Returns:
            List of SearchResult objects sorted by relevance
        """
        # Default search directory
        if search_dir is None:
            search_dir = Path.home() / ".claude" / "projects"

        # Validate search directory
        if not search_dir.exists():
            raise ValueError(f"Search directory does not exist: {search_dir}")

        # Return empty results for empty query
        if not query or not query.strip():
            return []

        # Find all JSONL files
        jsonl_files = list(search_dir.rglob("*.jsonl"))
        if not jsonl_files:
            return []

        # Apply date filtering to files if provided
        if date_from or date_to:
            jsonl_files = self._filter_files_by_date(jsonl_files, date_from, date_to)

        # Search based on mode
        all_results = []

        for jsonl_file in jsonl_files:
            if mode == "regex":
                results = self._search_regex(
                    jsonl_file, query, speaker_filter, case_sensitive
                )
            elif mode == "exact":
                results = self._search_exact(
                    jsonl_file, query, speaker_filter, case_sensitive
                )
            elif mode == "semantic" and self.nlp:
                results = self._search_semantic(jsonl_file, query, speaker_filter)
            else:  # smart mode - combines multiple approaches
                results = self._search_smart(
                    jsonl_file, query, speaker_filter, case_sensitive
                )

            all_results.extend(results)

        # Sort by relevance score
        all_results.sort(key=lambda x: x.relevance_score, reverse=True)

        # Return top results
        return all_results[:max_results]

    def _filter_files_by_date(
        self,
        files: List[Path],
        date_from: Optional[datetime],
        date_to: Optional[datetime],
    ) -> List[Path]:
        """Filter files by modification date."""
        filtered = []

        for file in files:
            file_mtime = datetime.fromtimestamp(file.stat().st_mtime)

            if date_from and file_mtime < date_from:
                continue
            if date_to and file_mtime > date_to:
                continue

            filtered.append(file)

        return filtered

    def _search_smart(
        self,
        jsonl_file: Path,
        query: str,
        speaker_filter: Optional[str],
        case_sensitive: bool,
    ) -> List[SearchResult]:
        """
        Smart search that combines multiple techniques.

        Uses exact matching, fuzzy matching, and semantic similarity.
        """
        results = []
        conversation_id = jsonl_file.stem

        # Process query
        if not case_sensitive:
            query_lower = query.lower()
            query_tokens = set(query_lower.split()) - self.stop_words
        else:
            query_tokens = set(query.split()) - self.stop_words

        # Read and parse JSONL
        try:
            with open(jsonl_file, "r", encoding="utf-8") as f:
                line_num = 0
                for line in f:
                    line_num += 1
                    try:
                        entry = json.loads(line.strip())

                        # Extract message based on entry type
                        if entry.get("type") in ["user", "assistant"]:
                            speaker = (
                                "human" if entry["type"] == "user" else "assistant"
                            )

                            # Apply speaker filter
                            if speaker_filter and speaker != speaker_filter:
                                continue

                            # Extract content
                            content = self._extract_content(entry)
                            if not content:
                                continue

                            # Calculate relevance
                            relevance = self._calculate_relevance(
                                content, query, query_tokens, case_sensitive
                            )

                            if relevance > RELEVANCE_THRESHOLD:  # Threshold for inclusion
                                # Extract context
                                context = self._extract_context(
                                    content, query, case_sensitive
                                )

                                # Parse timestamp if present
                                timestamp = None
                                timestamp_str = entry.get("timestamp")
                                if timestamp_str:
                                    try:
                                        timestamp = datetime.fromisoformat(
                                            timestamp_str.replace("Z", "+00:00")
                                        )
                                    except ValueError:
                                        pass

                                result = SearchResult(
                                    file_path=jsonl_file,
                                    conversation_id=conversation_id,
                                    matched_content=content[:MAX_CONTENT_LENGTH],
                                    context=context,
                                    speaker=speaker,
                                    timestamp=timestamp,
                                    relevance_score=relevance,
                                    line_number=line_num,
                                )
                                results.append(result)

                    except json.JSONDecodeError:
                        continue

        except Exception as e:
            print(f"Error searching {jsonl_file}: {e}")

        return results

    def _search_exact(
        self,
        jsonl_file: Path,
        query: str,
        speaker_filter: Optional[str],
        case_sensitive: bool,
    ) -> List[SearchResult]:
        """Exact string matching search."""
        results = []
        conversation_id = jsonl_file.stem

        search_query = query if case_sensitive else query.lower()

        try:
            with open(jsonl_file, "r", encoding="utf-8") as f:
                line_num = 0
                for line in f:
                    line_num += 1
                    try:
                        entry = json.loads(line.strip())

                        if entry.get("type") in ["user", "assistant"]:
                            speaker = (
                                "human" if entry["type"] == "user" else "assistant"
                            )

                            if speaker_filter and speaker != speaker_filter:
                                continue

                            content = self._extract_content(entry)
                            if not content:
                                continue

                            search_content = (
                                content if case_sensitive else content.lower()
                            )

                            if search_query in search_content:
                                # Calculate relevance based on match frequency
                                match_count = search_content.count(search_query)
                                relevance = min(MIN_RELEVANCE_COMPARED, match_count * MATCH_FACTOR_FOR_RELEVANCE)

                                context = self._extract_context(
                                    content, query, case_sensitive
                                )

                                # Parse timestamp if present
                                timestamp = None
                                timestamp_str = entry.get("timestamp")
                                if timestamp_str:
                                    try:
                                        timestamp = datetime.fromisoformat(
                                            timestamp_str.replace("Z", "+00:00")
                                        )
                                    except ValueError:
                                        pass

                                result = SearchResult(
                                    file_path=jsonl_file,
                                    conversation_id=conversation_id,
                                    matched_content=content[:MAX_CONTENT_LENGTH],
                                    context=context,
                                    speaker=speaker,
                                    timestamp=timestamp,
                                    relevance_score=relevance,
                                    line_number=line_num,
                                )
                                results.append(result)

                    except json.JSONDecodeError:
                        continue

        except Exception as e:
            print(f"Error searching {jsonl_file}: {e}")

        return results

    def _search_regex(
        self,
        jsonl_file: Path,
        pattern: str,
        speaker_filter: Optional[str],
        case_sensitive: bool,
    ) -> List[SearchResult]:
        """Regex pattern matching search."""
        results = []
        conversation_id = jsonl_file.stem

        # Compile regex pattern
        try:
            flags = 0 if case_sensitive else re.IGNORECASE
            regex = re.compile(pattern, flags)
        except re.error as e:
            print(f"Invalid regex pattern: {e}")
            return []

        try:
            with open(jsonl_file, "r", encoding="utf-8") as f:
                line_num = 0
                for line in f:
                    line_num += 1
                    try:
                        entry = json.loads(line.strip())

                        if entry.get("type") in ["user", "assistant"]:
                            speaker = (
                                "human" if entry["type"] == "user" else "assistant"
                            )

                            if speaker_filter and speaker != speaker_filter:
                                continue

                            content = self._extract_content(entry)
                            if not content:
                                continue

                            matches = list(regex.finditer(content))

                            if matches:
                                # Calculate relevance based on match quality
                                relevance = min(MIN_RELEVANCE_COMPARED, len(matches) * MATCH_FACTOR_FOR_RELEVANCE)

                                # Get context around first match
                                first_match = matches[0]
                                start = max(0, first_match.start() - MATCH_CONTEXT_STEP)
                                end = min(len(content), first_match.end() + MATCH_CONTEXT_STEP)
                                context = "..." + content[start:end] + "..."

                                # Parse timestamp if present
                                timestamp = None
                                timestamp_str = entry.get("timestamp")
                                if timestamp_str:
                                    try:
                                        timestamp = datetime.fromisoformat(
                                            timestamp_str.replace("Z", "+00:00")
                                        )
                                    except ValueError:
                                        pass

                                result = SearchResult(
                                    file_path=jsonl_file,
                                    conversation_id=conversation_id,
                                    matched_content=first_match.group(),
                                    context=context,
                                    speaker=speaker,
                                    timestamp=timestamp,
                                    relevance_score=relevance,
                                    line_number=line_num,
                                )
                                results.append(result)

                    except json.JSONDecodeError:
                        continue

        except Exception as e:
            print(f"Error searching {jsonl_file}: {e}")

        return results

    def _search_semantic(
        self, jsonl_file: Path, query: str, speaker_filter: Optional[str]
    ) -> List[SearchResult]:
        """
        Semantic search using spaCy NLP.

        Finds conceptually similar content even without exact matches.
        """
        if not self.nlp:
            return []

        results = []
        conversation_id = jsonl_file.stem

        # Process query with spaCy
        query_doc = self.nlp(query.lower())
        query_tokens = [
            token for token in query_doc if not token.is_stop and token.is_alpha
        ]

        try:
            with open(jsonl_file, "r", encoding="utf-8") as f:
                line_num = 0
                for line in f:
                    line_num += 1
                    try:
                        entry = json.loads(line.strip())

                        if entry.get("type") in ["user", "assistant"]:
                            speaker = (
                                "human" if entry["type"] == "user" else "assistant"
                            )

                            if speaker_filter and speaker != speaker_filter:
                                continue

                            content = self._extract_content(entry)
                            if not content:
                                continue

                            # Process content with spaCy
                            content_doc = self.nlp(content.lower())

                            # Calculate semantic similarity
                            similarity = self._calculate_semantic_similarity(
                                query_doc, query_tokens, content_doc
                            )

                            if similarity > SEMANTIC_SIMILARITY_THRESHOLD:  # Threshold for semantic matches
                                context = self._extract_context(content, query, False)

                                # Parse timestamp if present
                                timestamp = None
                                timestamp_str = entry.get("timestamp")
                                if timestamp_str:
                                    try:
                                        timestamp = datetime.fromisoformat(
                                            timestamp_str.replace("Z", "+00:00")
                                        )
                                    except ValueError:
                                        pass

                                result = SearchResult(
                                    file_path=jsonl_file,
                                    conversation_id=conversation_id,
                                    matched_content=content[:MAX_CONTENT_LENGTH],
                                    context=context,
                                    speaker=speaker,
                                    timestamp=timestamp,
                                    relevance_score=similarity,
                                    line_number=line_num,
                                )
                                results.append(result)

                    except json.JSONDecodeError:
                        continue

        except Exception as e:
            print(f"Error searching {jsonl_file}: {e}")

        return results

    def _extract_content(self, entry: Dict) -> str:
        """Extract text content from a JSONL entry."""
        # Handle test format (type: user/assistant, content: string)
        if entry.get("type") in ["user", "assistant"] and "content" in entry:
            content = entry["content"]
            if isinstance(content, str):
                return content

        # Handle actual Claude log format (type: user/assistant, message: {...})
        if "message" in entry:
            msg = entry["message"]
            if isinstance(msg, dict):
                content = msg.get("content", "")

                # Handle different content formats
                if isinstance(content, list):
                    # Extract text from content array
                    text_parts = []
                    for item in content:
                        if isinstance(item, dict) and item.get("type") == "text":
                            text_parts.append(item.get("text", ""))
                        elif isinstance(item, str):
                            text_parts.append(item)
                    return " ".join(text_parts)
                elif isinstance(content, str):
                    return content

        return ""

    def _calculate_relevance(
        self, content: str, query: str, query_tokens: Set[str], case_sensitive: bool
    ) -> float:
        """
        Calculate relevance score for content against query.

        Uses multiple factors:
        - Exact match bonus
        - Token overlap
        - Proximity of terms
        - Match density
        """
        relevance = 0.0

        # Prepare content
        if not case_sensitive:
            content_lower = content.lower()
            query_lower = query.lower()
        else:
            content_lower = content
            query_lower = query

        # Exact match bonus
        if query_lower in content_lower:
            relevance += MATCH_BONUS
            # Additional bonus for multiple occurrences
            count = content_lower.count(query_lower)
            relevance += min(MIN_RELEVANCE_MULTIPLE_OCCURRENCES, count * MATCH_FACTOR_MULTIPLE_OCCURRENCES)

        # Token overlap
        content_tokens = set(content_lower.split()) - self.stop_words
        if query_tokens and content_tokens:
            overlap = len(query_tokens & content_tokens)
            relevance += min(MIN_RELEVANCE_OVERLAP, overlap / len(query_tokens) * MATCH_FACTOR_OVERLAP)

        # Proximity bonus - are query terms near each other?
        if len(query_tokens) > MIN_TOKENS_FOR_PROXIMITY_BONUS:
            # Check if all query tokens appear within a window
            words = content_lower.split()
            for i in range(len(words) - len(query_tokens)):
                window = set(words[i : i + len(query_tokens) * PROXIMITY_WINDOW_MULTIPLIER])
                if query_tokens.issubset(window):
                    relevance += PROXIMITY_BONUS
                    break

        return min(MIN_RELEVANCE_COMPARED, relevance)

    def _calculate_semantic_similarity(
        self, query_doc, query_tokens, content_doc
    ) -> float:
        """Calculate semantic similarity using spaCy."""
        if not query_tokens:
            return 0.0

        # Find semantically similar tokens
        similar_count = 0
        for query_token in query_tokens:
            for content_token in content_doc:
                if content_token.is_alpha and not content_token.is_stop:
                    # Check if tokens are similar (same lemma or high similarity)
                    if (
                        query_token.lemma_ == content_token.lemma_
                        or query_token.text == content_token.text
                    ):
                        similar_count += 1
                        break

        # Calculate similarity score
        if query_tokens:
            base_similarity = similar_count / len(query_tokens)
        else:
            base_similarity = 0.0

        # Boost for exact phrase matches
        if query_doc.text.lower() in content_doc.text.lower():
            base_similarity = min(MIN_RELEVANCE_COMPARED, base_similarity + ADDITIONAL_BOOST_EXACT_MATCH)

        return base_similarity

    def _extract_context(
        self, content: str, query: str, case_sensitive: bool, context_size: int = DEFAULT_CONTEXT_SIZE
    ) -> str:
        """Extract context around the match for display."""
        if not case_sensitive:
            # Find match position
            pos = content.lower().find(query.lower())
        else:
            pos = content.find(query)

        if pos == -1:
            # No exact match, return beginning of content
            return content[: context_size * CONTEXT_FALLBACK_MULTIPLIER] + (
                "..." if len(content) > context_size * CONTEXT_FALLBACK_MULTIPLIER else ""
            )

        # Extract context around match
        start = max(0, pos - context_size)
        end = min(len(content), pos + len(query) + context_size)

        context = content[start:end]

        # Add ellipsis if truncated
        if start > 0:
            context = "..." + context
        if end < len(content):
            context = context + "..."

        # Highlight the match
        if not case_sensitive:
            # Case-insensitive replacement
            pattern = re.compile(re.escape(query), re.IGNORECASE)
            context = pattern.sub(f"**{query.upper()}**", context)
        else:
            context = context.replace(query, f"**{query}**")

        return context

    def search_by_date_range(
        self, date_from: datetime, date_to: datetime, search_dir: Optional[Path] = None
    ) -> List[Path]:
        """Find all conversation files within a date range."""
        if search_dir is None:
            search_dir = Path.home() / ".claude" / "projects"

        jsonl_files = list(search_dir.rglob("*.jsonl"))
        return self._filter_files_by_date(jsonl_files, date_from, date_to)

    def get_conversation_topics(
        self, jsonl_file: Path, max_topics: int = DEFAULT_MAX_TOPICS
    ) -> List[str]:
        """
        Extract main topics from a conversation.

        Uses NLP to identify key themes and subjects.
        """
        if not self.nlp:
            return []

        # Collect all content
        all_content = []
        try:
            with open(jsonl_file, "r", encoding="utf-8") as f:
                for line in f:
                    try:
                        entry = json.loads(line.strip())
                        content = self._extract_content(entry)
                        if content:
                            all_content.append(content)
                    except json.JSONDecodeError:
                        continue
        except Exception:
            return []

        if not all_content:
            return []

        # Process with spaCy
        full_text = " ".join(all_content[:CONTENT_LENGTH_PROCESSING])  # Limit to avoid processing too much
        doc = self.nlp(full_text)

        # Extract noun phrases as topics
        noun_phrases = []
        for chunk in doc.noun_chunks:
            if len(chunk.text.split()) <= MAX_NOUN_PHRASES_LENGTH:  # Reasonable length
                noun_phrases.append(chunk.text.lower())

        # Count frequency
        phrase_counts = {}
        for phrase in noun_phrases:
            phrase_counts[phrase] = phrase_counts.get(phrase, 0) + 1

        # Sort by frequency
        sorted_phrases = sorted(phrase_counts.items(), key=lambda x: x[1], reverse=True)

        # Return top topics
        return [phrase for phrase, count in sorted_phrases[:max_topics] if count > MIN_TOPIC_PHRASE_COUNT]


def create_search_index(search_dir: Path, output_file: Path) -> None:
    """
    Create a search index for faster subsequent searches.

    This pre-processes all conversations and saves metadata.
    """
    index = {"created": datetime.now().isoformat(), "conversations": {}}

    jsonl_files = list(search_dir.rglob("*.jsonl"))

    for jsonl_file in jsonl_files:
        conv_id = jsonl_file.stem

        # Extract metadata
        metadata = {
            "path": str(jsonl_file),
            "modified": datetime.fromtimestamp(jsonl_file.stat().st_mtime).isoformat(),
            "size": jsonl_file.stat().st_size,
            "message_count": 0,
            "speakers": set(),
            "first_message": None,
            "last_message": None,
        }

        # Parse file
        try:
            with open(jsonl_file, "r", encoding="utf-8") as f:
                for line in f:
                    try:
                        entry = json.loads(line.strip())
                        if entry.get("type") in ["user", "assistant"]:
                            metadata["message_count"] += 1
                            speaker = (
                                "human" if entry["type"] == "user" else "assistant"
                            )
                            metadata["speakers"].add(speaker)

                            if metadata["first_message"] is None:
                                metadata["first_message"] = entry.get("timestamp")
                            metadata["last_message"] = entry.get("timestamp")

                    except json.JSONDecodeError:
                        continue
        except Exception:
            continue

        # Convert set to list for JSON serialization
        metadata["speakers"] = list(metadata["speakers"])

        index["conversations"][conv_id] = metadata

    # Save index
    with open(output_file, "w") as f:
        json.dump(index, f, indent=INDENT_NUMBER)

    print(f"Created search index with {len(index['conversations'])} conversations")


# Example usage and testing
if __name__ == "__main__":
    # Test the search functionality
    searcher = ConversationSearcher()

    # Example searches
    print("Testing search functionality...")

    # Smart search
    results = searcher.search("python error", mode="smart", max_results=5)
    print(f"\nFound {len(results)} results for 'python error'")
    for result in results[:2]:
        print(result)

    # Regex search
    results = searcher.search(r"import\s+\w+", mode="regex", max_results=5)
    print(f"\nFound {len(results)} results for regex 'import\\s+\\w+'")

    # Date range search
    week_ago = datetime.now() - timedelta(days=7)
    results = searcher.search("", date_from=week_ago, max_results=5)
    print(f"\nFound {len(results)} conversations from the last week")

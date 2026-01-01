#!/usr/bin/env python3
"""
Shared constants for Claude Conversation Extractor

This module centralizes all magic numbers and configuration values
to improve maintainability and consistency across the codebase.
"""

# =============================================================================
# Display Constants
# =============================================================================

# Separator widths for console output
MAJOR_SEPARATOR_WIDTH = 60
MINOR_SEPARATOR_WIDTH = 40
LIST_SEPARATOR_WIDTH = 80

# JSON formatting
INDENT_NUMBER = 2

# Session ID display
SESSION_ID_MAX_LENGTH = 8

# =============================================================================
# Message Display Constants
# =============================================================================

LINES_SHOWN_MESSAGE = 8
LINES_PER_PAGE_MESSAGE = 30
MAX_LINES_PER_MESSAGE_DISPLAY = 50
MAX_LINE_LENGTH_DISPLAY = 100

# =============================================================================
# Preview and Truncation Constants
# =============================================================================

MIN_PREVIEW_TEXT_LENGTH = 3
PREVIEW_TEXT_TRUNCATE_LENGTH = 100
PREVIEW_ERROR_TRUNCATE_LENGTH = 30
MAX_PREVIEW_LENGTH = 60
MAX_CONTENT_LENGTH = 200

# =============================================================================
# Search Constants
# =============================================================================

SEARCH_MAX_RESULTS_DEFAULT = 30
DEFAULT_MAX_RESULTS = 20
DEFAULT_CONTEXT_SIZE = 150

# =============================================================================
# UI Constants
# =============================================================================

SESSION_DISPLAY_LIMIT = 20
PROJECT_LENGTH = 30
PROGRESS_BAR_WIDTH = 40
RECENT_SESSIONS_LIMIT = 5

# =============================================================================
# Search Relevance Constants
# =============================================================================

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

# =============================================================================
# Topic Extraction Constants
# =============================================================================

DEFAULT_MAX_TOPICS = 5
CONTENT_LENGTH_PROCESSING = 10
MAX_NOUN_PHRASES_LENGTH = 3
MIN_TOPIC_PHRASE_COUNT = 1

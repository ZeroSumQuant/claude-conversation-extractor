#!/usr/bin/env python3
"""
Sample conversations for testing search functionality
"""

import json
from datetime import datetime, timedelta
from pathlib import Path
import tempfile

# Sample conversation data that covers various scenarios
SAMPLE_CONVERSATIONS = [
    {
        "id": "python_errors",
        "messages": [
            {
                "type": "user",
                "content": "How do I handle Python errors?",
                "timestamp": "2024-01-15T10:00:00Z"
            },
            {
                "type": "assistant",
                "content": "To handle errors in Python, use try-except blocks. Here's an example:\n\n```python\ntry:\n    risky_operation()\nexcept ValueError as e:\n    print(f'Error: {e}')\n```",
                "timestamp": "2024-01-15T10:01:00Z"
            },
            {
                "type": "user",
                "content": "What about handling multiple exception types?",
                "timestamp": "2024-01-15T10:02:00Z"
            },
            {
                "type": "assistant",
                "content": "You can handle multiple exceptions using multiple except blocks or a tuple of exception types.",
                "timestamp": "2024-01-15T10:03:00Z"
            }
        ]
    },
    {
        "id": "file_operations",
        "messages": [
            {
                "type": "user",
                "content": "Can you show me how to read and write files in Python?",
                "timestamp": "2024-01-16T14:30:00Z"
            },
            {
                "type": "assistant",
                "content": "Here's how to work with files:\n\n```python\n# Reading\nwith open('file.txt', 'r') as f:\n    content = f.read()\n\n# Writing\nwith open('output.txt', 'w') as f:\n    f.write('Hello, World!')\n```",
                "timestamp": "2024-01-16T14:31:00Z"
            }
        ]
    },
    {
        "id": "regex_patterns",
        "messages": [
            {
                "type": "user",
                "content": "I need help with regex patterns for email validation",
                "timestamp": "2024-01-17T09:15:00Z"
            },
            {
                "type": "assistant",
                "content": "Here's a regex pattern for email validation:\n\n```python\nimport re\n\npattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$'\nemail = 'user@example.com'\n\nif re.match(pattern, email):\n    print('Valid email')\n```",
                "timestamp": "2024-01-17T09:16:00Z"
            }
        ]
    },
    {
        "id": "api_requests",
        "messages": [
            {
                "type": "user",
                "content": "How do I make API requests in Python?",
                "timestamp": "2024-01-18T16:45:00Z"
            },
            {
                "type": "assistant",
                "content": "You can use the requests library:\n\n```python\nimport requests\n\nresponse = requests.get('https://api.example.com/data')\nif response.status_code == 200:\n    data = response.json()\n```",
                "timestamp": "2024-01-18T16:46:00Z"
            }
        ]
    },
    {
        "id": "database_connection",
        "messages": [
            {
                "type": "user",
                "content": "What's the best way to connect to a PostgreSQL database?",
                "timestamp": "2024-01-19T11:20:00Z"
            },
            {
                "type": "assistant",
                "content": "I recommend using psycopg2 or SQLAlchemy for PostgreSQL connections.",
                "timestamp": "2024-01-19T11:21:00Z"
            }
        ]
    }
]


class ConversationFixtures:
    """Helper class to create test conversation files"""
    
    @staticmethod
    def create_test_environment():
        """Create a temporary directory with sample conversations"""
        temp_dir = tempfile.mkdtemp()
        claude_dir = Path(temp_dir) / ".claude" / "projects"
        
        # Create conversations in different project directories
        projects = ["python_help", "web_dev", "data_science"]
        
        all_files = []
        conversation_idx = 0
        
        for project in projects:
            project_dir = claude_dir / project
            project_dir.mkdir(parents=True)
            
            # Create 1-2 conversations per project
            for i in range(min(2, len(SAMPLE_CONVERSATIONS) - conversation_idx)):
                if conversation_idx >= len(SAMPLE_CONVERSATIONS):
                    break
                    
                conv_data = SAMPLE_CONVERSATIONS[conversation_idx]
                chat_file = project_dir / f"chat_{conv_data['id']}.jsonl"
                
                # Write messages as JSONL
                with open(chat_file, 'w') as f:
                    for msg in conv_data['messages']:
                        f.write(json.dumps(msg) + '\n')
                
                all_files.append(chat_file)
                conversation_idx += 1
        
        return temp_dir, all_files
    
    @staticmethod
    def get_expected_search_results():
        """Get expected search results for various queries"""
        return {
            # Exact matches
            "Python errors": ["python_errors"],
            "PostgreSQL database": ["database_connection"],
            
            # Partial matches
            "python": ["python_errors", "file_operations", "api_requests"],
            "error": ["python_errors"],
            "file": ["file_operations"],
            "regex": ["regex_patterns"],
            "API": ["api_requests"],
            
            # Case insensitive
            "PYTHON": ["python_errors", "file_operations", "api_requests"],
            
            # Multi-word
            "handle errors": ["python_errors"],
            "read write files": ["file_operations"],
            
            # Code snippets
            "try except": ["python_errors"],
            "requests.get": ["api_requests"],
            "open file": ["file_operations"],
            
            # Regex patterns
            r"except \w+Error": ["python_errors"],
            r"@[a-zA-Z0-9.-]+": ["regex_patterns"],
            
            # No matches
            "javascript": [],
            "rust programming": [],
        }
    
    @staticmethod
    def get_date_filtered_results():
        """Get expected results for date-filtered searches"""
        # Assuming we set file modification times appropriately
        return {
            # Last 2 days (should get latest conversations)
            ("python", 2): ["api_requests", "database_connection"],
            
            # Last 5 days (should get all)
            ("python", 5): ["python_errors", "file_operations", "api_requests"],
            
            # Specific date range
            ("error", "2024-01-15", "2024-01-16"): ["python_errors"],
        }
    
    @staticmethod
    def get_speaker_filtered_results():
        """Get expected results for speaker-filtered searches"""
        return {
            # Human only
            ("Python", "human"): ["python_errors", "file_operations", "api_requests"],
            
            # Assistant only  
            ("try-except", "assistant"): ["python_errors"],
            ("SQLAlchemy", "assistant"): ["database_connection"],
        }


def cleanup_test_environment(temp_dir):
    """Clean up the test environment"""
    import shutil
    shutil.rmtree(temp_dir, ignore_errors=True)
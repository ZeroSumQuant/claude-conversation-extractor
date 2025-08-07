use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClaudeConversation {
    pub id: String,
    pub title: String,
    pub created_at: String,
    pub updated_at: String,
    pub messages: Vec<Message>,
    pub metadata: ConversationMetadata,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub role: String,
    pub content: String,
    pub timestamp: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversationMetadata {
    pub project: Option<String>,
    pub tags: Vec<String>,
    pub model: Option<String>,
}

pub struct ConversationParser;

impl ConversationParser {
    pub fn new() -> Self {
        Self
    }
    
    pub async fn parse_file(&self, path: &Path) -> Result<ClaudeConversation> {
        let content = tokio::fs::read_to_string(path).await?;
        self.parse_content(&content)
    }
    
    pub fn parse_content(&self, content: &str) -> Result<ClaudeConversation> {
        // Try to parse as JSON first
        if let Ok(conv) = serde_json::from_str::<ClaudeConversation>(content) {
            return Ok(conv);
        }
        
        // Fallback to custom parsing logic for Claude's format
        self.parse_claude_format(content)
    }
    
    fn parse_claude_format(&self, content: &str) -> Result<ClaudeConversation> {
        // This would implement parsing of Claude's specific conversation format
        // For now, return a sample conversation
        
        let messages = self.extract_messages(content);
        let title = self.extract_title(content).unwrap_or_else(|| "Untitled".to_string());
        
        Ok(ClaudeConversation {
            id: uuid::Uuid::new_v4().to_string(),
            title,
            created_at: chrono::Local::now().to_rfc3339(),
            updated_at: chrono::Local::now().to_rfc3339(),
            messages,
            metadata: ConversationMetadata {
                project: None,
                tags: Vec::new(),
                model: Some("claude-3".to_string()),
            },
        })
    }
    
    fn extract_messages(&self, content: &str) -> Vec<Message> {
        let mut messages = Vec::new();
        
        // Simple pattern matching for demonstration
        // In production, this would be more sophisticated
        for line in content.lines() {
            if line.starts_with("User:") {
                messages.push(Message {
                    role: "user".to_string(),
                    content: line.strip_prefix("User:").unwrap_or("").trim().to_string(),
                    timestamp: Some(chrono::Local::now().to_rfc3339()),
                });
            } else if line.starts_with("Assistant:") {
                messages.push(Message {
                    role: "assistant".to_string(),
                    content: line.strip_prefix("Assistant:").unwrap_or("").trim().to_string(),
                    timestamp: Some(chrono::Local::now().to_rfc3339()),
                });
            }
        }
        
        messages
    }
    
    fn extract_title(&self, content: &str) -> Option<String> {
        // Extract title from content
        // This is a simplified version
        content
            .lines()
            .find(|line| !line.trim().is_empty())
            .map(|line| {
                let title = line.trim();
                if title.len() > 100 {
                    format!("{}...", &title[..97])
                } else {
                    title.to_string()
                }
            })
    }
    
    pub fn extract_text(&self, conversation: &ClaudeConversation) -> String {
        let mut text = String::new();
        
        for message in &conversation.messages {
            text.push_str(&format!("{}: {}\n\n", message.role, message.content));
        }
        
        text
    }
}
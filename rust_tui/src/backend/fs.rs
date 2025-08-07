use crate::state::{Conversation, FileNode, FileTree};
use anyhow::Result;
use chrono::Local;
use lru::LruCache;
use parking_lot::RwLock;
use std::num::NonZeroUsize;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use walkdir::WalkDir;

pub struct ConversationManager {
    claude_dir: PathBuf,
    cache: Arc<RwLock<LruCache<PathBuf, Conversation>>>,
}

impl ConversationManager {
    pub async fn new() -> Result<Self> {
        let claude_dir = dirs::home_dir()
            .ok_or_else(|| anyhow::anyhow!("Could not find home directory"))?
            .join(".claude")
            .join("projects");
        
        let cache = Arc::new(RwLock::new(LruCache::new(
            NonZeroUsize::new(1000).unwrap(),
        )));
        
        Ok(Self { claude_dir, cache })
    }
    
    pub async fn load_all(&self) -> Result<Vec<Conversation>> {
        let mut conversations = Vec::new();
        
        // Use rayon for parallel processing
        let paths: Vec<_> = WalkDir::new(&self.claude_dir)
            .into_iter()
            .filter_map(|e| e.ok())
            .filter(|e| {
                let ext = e.path().extension().and_then(|s| s.to_str());
                ext == Some("jsonl") || ext == Some("json")
            })
            .map(|e| e.path().to_owned())
            .collect();
        
        for path in paths {
            if let Ok(conv) = self.load_conversation(&path).await {
                conversations.push(conv);
            }
        }
        
        // Sort by updated_at descending
        conversations.sort_by(|a, b| b.updated_at.cmp(&a.updated_at));
        
        Ok(conversations)
    }
    
    pub async fn load_conversation(&self, path: &Path) -> Result<Conversation> {
        // Check cache first
        {
            let cache = self.cache.read();
            if let Some(conv) = cache.peek(&path.to_path_buf()) {
                return Ok(conv.clone());
            }
        }
        
        // Load from disk
        let content = tokio::fs::read_to_string(path).await?;
        let conv = self.parse_conversation(&content, path)?;
        
        // Update cache
        {
            let mut cache = self.cache.write();
            cache.put(path.to_path_buf(), conv.clone());
        }
        
        Ok(conv)
    }
    
    fn parse_conversation(&self, content: &str, path: &Path) -> Result<Conversation> {
        let metadata = std::fs::metadata(path)?;
        
        // Parse JSONL to get actual conversation data
        let lines: Vec<&str> = content.lines().collect();
        let mut title = "Untitled".to_string();
        let mut message_count = 0;
        
        // Try to extract title from first user message
        for line in &lines {
            if line.contains("\"role\":\"user\"") || line.contains("\"role\": \"user\"") {
                message_count += 1;
                if title == "Untitled" {
                    // Try to extract content for title
                    if let Some(content_start) = line.find("\"content\":") {
                        let content_part = &line[content_start + 10..];
                        if let Some(start_quote) = content_part.find('"') {
                            let text_part = &content_part[start_quote + 1..];
                            if let Some(end_quote) = text_part.find('"') {
                                // Safely extract up to 50 chars
                                let max_len = end_quote.min(50);
                                // Ensure we don't cut in the middle of a UTF-8 character
                                if let Some(s) = text_part.get(..max_len) {
                                    title = s.to_string();
                                } else {
                                    // Fallback to char boundary
                                    let mut boundary = max_len;
                                    while !text_part.is_char_boundary(boundary) && boundary > 0 {
                                        boundary -= 1;
                                    }
                                    if boundary > 0 {
                                        title = text_part[..boundary].to_string();
                                    }
                                }
                            }
                        }
                    }
                }
            } else if line.contains("\"role\":\"assistant\"") || line.contains("\"role\": \"assistant\"") {
                message_count += 1;
            }
        }
        
        let project = path
            .parent()
            .and_then(|p| p.file_name())
            .and_then(|n| n.to_str())
            .unwrap_or("unknown")
            .to_string();
        
        // Use file modification time
        let modified = metadata.modified()
            .unwrap_or_else(|_| std::time::SystemTime::now());
        let created = metadata.created()
            .unwrap_or_else(|_| std::time::SystemTime::now());
        
        Ok(Conversation {
            id: path.to_string_lossy().to_string(),
            title,
            project,
            created_at: chrono::DateTime::<Local>::from(created),
            updated_at: chrono::DateTime::<Local>::from(modified),
            message_count,
            size_bytes: metadata.len(),
            path: path.to_path_buf(),
            tags: Vec::new(),
        })
    }
    
    pub async fn get_recent(&self, limit: usize) -> Result<Vec<Conversation>> {
        let all = self.load_all().await?;
        Ok(all.into_iter().take(limit).collect())
    }
    
    pub async fn count_conversations(&self) -> Result<usize> {
        let count = WalkDir::new(&self.claude_dir)
            .into_iter()
            .filter_map(|e| e.ok())
            .filter(|e| {
                let ext = e.path().extension().and_then(|s| s.to_str());
                ext == Some("jsonl") || ext == Some("json")
            })
            .count();
        
        Ok(count)
    }
    
    pub async fn calculate_total_size(&self) -> Result<u64> {
        let total = WalkDir::new(&self.claude_dir)
            .into_iter()
            .filter_map(|e| e.ok())
            .filter(|e| {
                let ext = e.path().extension().and_then(|s| s.to_str());
                ext == Some("jsonl") || ext == Some("json")
            })
            .filter_map(|e| std::fs::metadata(e.path()).ok())
            .map(|m| m.len())
            .sum();
        
        Ok(total)
    }
    
    pub async fn build_file_tree(&self) -> Result<FileTree> {
        let mut tree = FileTree {
            root: self.claude_dir.clone(),
            nodes: Vec::new(),
            loaded: false,
        };
        
        tree.nodes = self.build_nodes(&self.claude_dir, 0).await?;
        tree.loaded = true;
        
        Ok(tree)
    }
    
    fn build_nodes<'a>(&'a self, path: &'a Path, depth: usize) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Vec<FileNode>>> + Send + 'a>> {
        Box::pin(async move {
            if depth > 5 {
                // Limit depth to prevent deep recursion
                return Ok(Vec::new());
            }
            
            let mut nodes = Vec::new();
            let mut dir_entries = tokio::fs::read_dir(path).await?;
            
            while let Some(entry) = dir_entries.next_entry().await? {
                let path = entry.path();
                let metadata = entry.metadata().await?;
                let name = path.file_name()
                    .and_then(|n| n.to_str())
                    .unwrap_or("")
                    .to_string();
                
                // Skip hidden files
                if name.starts_with('.') {
                    continue;
                }
                
                let mut node = FileNode {
                    name,
                    path: path.clone(),
                    is_dir: metadata.is_dir(),
                    size: metadata.len(),
                    modified: metadata.modified()?.into(),
                    children: Vec::new(),
                    expanded: false,
                    depth,
                };
                
                if node.is_dir && depth < 2 {
                    // Lazy load only first two levels - use Box::pin for recursion
                    let child_future = self.build_nodes(&path, depth + 1);
                    node.children = child_future.await?;
                }
                
                nodes.push(node);
            }
            
            Ok(nodes)
        })
    }
    
    pub async fn calculate_stats(&self) -> Result<crate::state::Statistics> {
        // This would calculate real statistics from the conversations
        Ok(crate::state::Statistics::default())
    }
}
use crate::state::{Conversation, Match, SearchResult};
use anyhow::Result;
use fuzzy_matcher::skim::SkimMatcherV2;
use fuzzy_matcher::FuzzyMatcher;
use parking_lot::RwLock;
use rayon::prelude::*;
use regex::Regex;
use std::sync::Arc;

pub struct SearchEngine {
    matcher: Arc<SkimMatcherV2>,
    regex_cache: Arc<RwLock<lru::LruCache<String, Regex>>>,
}

impl SearchEngine {
    pub fn new() -> Self {
        Self {
            matcher: Arc::new(SkimMatcherV2::default()),
            regex_cache: Arc::new(RwLock::new(lru::LruCache::new(
                std::num::NonZeroUsize::new(100).unwrap(),
            ))),
        }
    }
    
    pub async fn search(&self, query: &str) -> Result<Vec<SearchResult>> {
        // This is a placeholder - in production, you'd search actual conversations
        let conversations = self.load_sample_conversations();
        
        let query = query.to_lowercase();
        let matcher = self.matcher.clone();
        
        let results: Vec<SearchResult> = conversations
            .par_iter()
            .filter_map(|conv| {
                let mut matches = Vec::new();
                let mut total_score = 0.0;
                
                // Search in title
                if let Some(score) = matcher.fuzzy_match(&conv.title.to_lowercase(), &query) {
                    total_score += score as f32;
                    matches.push(Match {
                        field: "title".to_string(),
                        text: conv.title.clone(),
                        positions: self.find_positions(&conv.title, &query),
                    });
                }
                
                // Search in project
                if let Some(score) = matcher.fuzzy_match(&conv.project.to_lowercase(), &query) {
                    total_score += score as f32 * 0.5; // Lower weight for project match
                    matches.push(Match {
                        field: "project".to_string(),
                        text: conv.project.clone(),
                        positions: self.find_positions(&conv.project, &query),
                    });
                }
                
                // Search in tags
                for tag in &conv.tags {
                    if let Some(score) = matcher.fuzzy_match(&tag.to_lowercase(), &query) {
                        total_score += score as f32 * 0.3; // Lower weight for tag match
                        matches.push(Match {
                            field: "tag".to_string(),
                            text: tag.clone(),
                            positions: self.find_positions(tag, &query),
                        });
                    }
                }
                
                if !matches.is_empty() {
                    Some(SearchResult {
                        conversation: conv.clone(),
                        score: (total_score / 100.0).min(1.0), // Normalize to 0-1
                        matches,
                    })
                } else {
                    None
                }
            })
            .collect();
        
        // Sort by score descending
        let mut results = results;
        results.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap());
        
        Ok(results)
    }
    
    pub async fn search_regex(&self, pattern: &str) -> Result<Vec<SearchResult>> {
        let regex = self.get_or_compile_regex(pattern)?;
        let conversations = self.load_sample_conversations();
        
        let results: Vec<SearchResult> = conversations
            .par_iter()
            .filter_map(|conv| {
                let mut matches = Vec::new();
                
                // Search in title
                if regex.is_match(&conv.title) {
                    matches.push(Match {
                        field: "title".to_string(),
                        text: conv.title.clone(),
                        positions: self.find_regex_positions(&conv.title, &regex),
                    });
                }
                
                // Search in project
                if regex.is_match(&conv.project) {
                    matches.push(Match {
                        field: "project".to_string(),
                        text: conv.project.clone(),
                        positions: self.find_regex_positions(&conv.project, &regex),
                    });
                }
                
                if !matches.is_empty() {
                    Some(SearchResult {
                        conversation: conv.clone(),
                        score: 1.0, // Regex matches are binary
                        matches,
                    })
                } else {
                    None
                }
            })
            .collect();
        
        Ok(results)
    }
    
    fn get_or_compile_regex(&self, pattern: &str) -> Result<Regex> {
        {
            let cache = self.regex_cache.read();
            if let Some(regex) = cache.peek(&pattern.to_string()) {
                return Ok(regex.clone());
            }
        }
        
        let regex = Regex::new(pattern)?;
        
        {
            let mut cache = self.regex_cache.write();
            cache.put(pattern.to_string(), regex.clone());
        }
        
        Ok(regex)
    }
    
    fn find_positions(&self, text: &str, query: &str) -> Vec<(usize, usize)> {
        let text_lower = text.to_lowercase();
        let query_lower = query.to_lowercase();
        
        let mut positions = Vec::new();
        let mut start = 0;
        
        while let Some(pos) = text_lower[start..].find(&query_lower) {
            let abs_pos = start + pos;
            positions.push((abs_pos, abs_pos + query.len()));
            start = abs_pos + 1;
        }
        
        positions
    }
    
    fn find_regex_positions(&self, text: &str, regex: &Regex) -> Vec<(usize, usize)> {
        regex
            .find_iter(text)
            .map(|m| (m.start(), m.end()))
            .collect()
    }
    
    fn load_sample_conversations(&self) -> Vec<Conversation> {
        // In production, this would load from the ConversationManager
        vec![
            Conversation {
                id: "1".to_string(),
                title: "Implementing Rust TUI".to_string(),
                project: "claude-extractor".to_string(),
                created_at: chrono::Local::now(),
                updated_at: chrono::Local::now(),
                message_count: 42,
                size_bytes: 12345,
                path: std::path::PathBuf::from("/sample/path"),
                tags: vec!["rust".to_string(), "tui".to_string()],
            },
            Conversation {
                id: "2".to_string(),
                title: "Python Integration".to_string(),
                project: "claude-extractor".to_string(),
                created_at: chrono::Local::now(),
                updated_at: chrono::Local::now(),
                message_count: 28,
                size_bytes: 8765,
                path: std::path::PathBuf::from("/sample/path2"),
                tags: vec!["python".to_string(), "pyo3".to_string()],
            },
        ]
    }
}
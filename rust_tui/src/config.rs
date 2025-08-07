use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tokio::fs;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub theme: String,
    pub claude_dir: PathBuf,
    pub export_dir: PathBuf,
    pub auto_sync: bool,
    pub sync_interval_minutes: u32,
    pub search_history_size: usize,
    pub show_hidden_files: bool,
    pub vim_mode: bool,
    pub confirm_on_delete: bool,
    pub notification_timeout_seconds: u32,
    pub max_recent_conversations: usize,
    pub cache_size_mb: usize,
    pub log_level: String,
}

impl Default for Config {
    fn default() -> Self {
        let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("."));
        
        Self {
            theme: "claude".to_string(),
            claude_dir: home.join(".claude").join("projects"),
            export_dir: home.join("Documents").join("claude-exports"),
            auto_sync: true,
            sync_interval_minutes: 60,
            search_history_size: 50,
            show_hidden_files: false,
            vim_mode: true,
            confirm_on_delete: true,
            notification_timeout_seconds: 5,
            max_recent_conversations: 10,
            cache_size_mb: 100,
            log_level: "info".to_string(),
        }
    }
}

impl Config {
    pub async fn load() -> Result<Self> {
        let config_path = Self::config_path()?;
        
        if config_path.exists() {
            let content = fs::read_to_string(&config_path).await?;
            let config: Self = toml::from_str(&content)?;
            Ok(config)
        } else {
            let config = Self::default();
            config.save().await?;
            Ok(config)
        }
    }
    
    pub async fn save(&self) -> Result<()> {
        let config_path = Self::config_path()?;
        
        // Ensure directory exists
        if let Some(parent) = config_path.parent() {
            fs::create_dir_all(parent).await?;
        }
        
        let content = toml::to_string_pretty(self)?;
        fs::write(&config_path, content).await?;
        
        Ok(())
    }
    
    fn config_path() -> Result<PathBuf> {
        let config_dir = dirs::config_dir()
            .ok_or_else(|| anyhow::anyhow!("Could not determine config directory"))?;
        
        Ok(config_dir.join("claude-tui").join("config.toml"))
    }
}
#[cfg(test)]
mod tests {
    use claude_tui::state::{AppState, Page};
    use claude_tui::config::Config;
    
    #[test]
    fn test_app_state_creation() {
        let state = AppState::new();
        assert_eq!(state.current_page, Page::Home);
        assert_eq!(state.total_conversations, 0);
        assert!(state.conversations.is_empty());
    }
    
    #[test]
    fn test_config_defaults() {
        let config = Config::default();
        assert_eq!(config.theme, "claude");
        assert_eq!(config.vim_mode, true);
        assert_eq!(config.search_history_size, 50);
    }
    
    #[test]
    fn test_theme_creation() {
        use claude_tui::ui::theme::Theme;
        
        let matrix = Theme::matrix();
        assert_eq!(matrix.name, "Matrix");
        
        let claude = Theme::claude();
        assert_eq!(claude.name, "Claude");
        
        let cyberpunk = Theme::cyberpunk();
        assert_eq!(cyberpunk.name, "Cyberpunk");
    }
    
    #[test]
    fn test_export_format() {
        use claude_tui::state::ExportFormat;
        
        let formats = vec![
            ExportFormat::Markdown,
            ExportFormat::Json,
            ExportFormat::Html,
            ExportFormat::Pdf,
            ExportFormat::Zip,
        ];
        
        assert_eq!(formats.len(), 5);
    }
}
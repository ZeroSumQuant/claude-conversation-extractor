use crate::{
    state::{Action, AppState},
    ui::theme::Theme,
};
use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::Modifier,
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem, Paragraph},
    Frame,
};

pub fn render(frame: &mut Frame, area: Rect, state: &mut AppState, theme: &Theme) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),   // Title
            Constraint::Min(10),     // Settings list
            Constraint::Length(3),   // Actions
        ])
        .split(area);
    
    render_title(frame, chunks[0], theme);
    render_settings_list(frame, chunks[1], state, theme);
    render_actions(frame, chunks[2], theme);
}

fn render_title(frame: &mut Frame, area: Rect, theme: &Theme) {
    let paragraph = Paragraph::new(Line::from(vec![
        Span::styled("Settings", theme.primary_style().add_modifier(Modifier::BOLD)),
        Span::styled(" - Configure Claude TUI", theme.muted_style()),
    ]))
    .block(
        Block::default()
            .borders(Borders::BOTTOM)
            .border_style(theme.border_style()),
    )
    .alignment(Alignment::Center);
    
    frame.render_widget(paragraph, area);
}

fn render_settings_list(frame: &mut Frame, area: Rect, state: &AppState, theme: &Theme) {
    // Create owned strings to avoid lifetime issues
    let auto_sync_str = format!("{}", state.settings.auto_sync);
    let sync_interval_str = format!("{} minutes", state.settings.sync_interval_minutes);
    let search_history_str = format!("{}", state.settings.search_history_size);
    let show_hidden_str = format!("{}", state.settings.show_hidden_files);
    let vim_mode_str = format!("{}", state.settings.vim_mode);
    let confirm_delete_str = format!("{}", state.settings.confirm_on_delete);
    let notif_timeout_str = format!("{} seconds", state.settings.notification_timeout_seconds);
    
    let settings = vec![
        (
            "Theme",
            state.settings.theme.as_str(),
            "Current color theme (matrix/claude/cyberpunk)",
        ),
        (
            "Auto Sync",
            auto_sync_str.as_str(),
            "Automatically sync conversations",
        ),
        (
            "Sync Interval",
            sync_interval_str.as_str(),
            "How often to sync (if auto-sync enabled)",
        ),
        (
            "Export Format",
            state.settings.default_export_format.as_str(),
            "Default format for exports",
        ),
        (
            "Search History Size",
            search_history_str.as_str(),
            "Number of search queries to remember",
        ),
        (
            "Show Hidden Files",
            show_hidden_str.as_str(),
            "Display hidden files in browser",
        ),
        (
            "Vim Mode",
            vim_mode_str.as_str(),
            "Use vim-style keybindings",
        ),
        (
            "Confirm Delete",
            confirm_delete_str.as_str(),
            "Ask for confirmation before deleting",
        ),
        (
            "Notification Timeout",
            notif_timeout_str.as_str(),
            "How long to show notifications",
        ),
    ];
    
    let items: Vec<ListItem> = settings
        .iter()
        .enumerate()
        .map(|(idx, (name, value, description))| {
            let name_span = Span::styled(
                format!("{:20}", name),
                theme.primary_style(),
            );
            
            let value_span = Span::styled(
                format!("{:15}", value),
                theme.accent_style().add_modifier(Modifier::BOLD),
            );
            
            let desc_span = Span::styled(
                format!(" - {}", description),
                theme.muted_style(),
            );
            
            ListItem::new(Line::from(vec![name_span, value_span, desc_span]))
        })
        .collect();
    
    let list = List::new(items)
        .block(
            theme
                .create_block("Configuration")
                .border_style(theme.secondary_style()),
        )
        .style(theme.base_style())
        .highlight_style(theme.selection_style())
        .highlight_symbol("> ");
    
    frame.render_widget(list, area);
}

fn render_actions(frame: &mut Frame, area: Rect, theme: &Theme) {
    let actions = vec![
        ("Enter", "Edit setting"),
        ("s", "Save changes"),
        ("r", "Reset to defaults"),
        ("t", "Toggle theme"),
        ("ESC", "Cancel"),
    ];
    
    let spans: Vec<Span> = actions
        .iter()
        .flat_map(|(key, action)| {
            vec![
                Span::styled(format!("[{}]", key), theme.accent_style()),
                Span::styled(format!(" {}  ", action), theme.primary_style()),
            ]
        })
        .collect();
    
    let paragraph = Paragraph::new(Line::from(spans))
        .block(
            Block::default()
                .borders(Borders::TOP)
                .border_style(theme.border_style()),
        )
        .alignment(Alignment::Center);
    
    frame.render_widget(paragraph, area);
}

pub fn handle_key(key: KeyEvent, _state: &AppState) -> Option<Action> {
    match (key.modifiers, key.code) {
        // Save settings
        (KeyModifiers::NONE, KeyCode::Char('s')) => Some(Action::SaveSettings),
        
        // Reset to defaults
        (KeyModifiers::NONE, KeyCode::Char('r')) => {
            Some(Action::ShowConfirm(
                "Reset Settings".to_string(),
                "Are you sure you want to reset all settings to defaults?".to_string(),
                Box::new(Action::ResetSettings),
            ))
        }
        
        // Toggle theme quickly
        (KeyModifiers::NONE, KeyCode::Char('t')) => {
            // This will be handled by the app to cycle themes
            None
        }
        
        // Edit selected setting
        (KeyModifiers::NONE, KeyCode::Enter) => {
            // Would open an input modal for the selected setting
            Some(Action::ShowInput(
                "Edit Setting".to_string(),
                "Enter new value:".to_string(),
                Box::new(Action::SaveSettings),
            ))
        }
        
        _ => None,
    }
}
use crate::{
    state::{Action, AppState},
    ui::theme::Theme,
};
use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Modifier, Style},
    text::{Line, Span, Text},
    widgets::{Block, Borders, List, ListItem, Paragraph, Sparkline},
    Frame,
};

pub fn render(frame: &mut Frame, area: Rect, state: &AppState, theme: &Theme) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(10),  // Stats overview
            Constraint::Min(5),      // Recent conversations
            Constraint::Length(3),   // Quick actions
        ])
        .split(area);
    
    render_stats_overview(frame, chunks[0], state, theme);
    render_recent_conversations(frame, chunks[1], state, theme);
    render_quick_actions(frame, chunks[2], theme);
}

fn render_stats_overview(frame: &mut Frame, area: Rect, state: &AppState, theme: &Theme) {
    let chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage(33),
            Constraint::Percentage(34),
            Constraint::Percentage(33),
        ])
        .split(area);
    
    // Total conversations
    let total_block = theme
        .create_block("Total Conversations")
        .border_style(theme.primary_style());
    
    let total_text = vec![
        Line::from(""),
        Line::from(Span::styled(
            format!("{}", state.total_conversations),
            theme.highlight_style().add_modifier(Modifier::BOLD),
        )),
        Line::from(""),
        Line::from(Span::styled(
            format!("Size: {:.2} MB", state.total_size as f64 / 1_048_576.0),
            theme.muted_style(),
        )),
    ];
    
    let total_paragraph = Paragraph::new(total_text)
        .block(total_block)
        .alignment(Alignment::Center);
    
    frame.render_widget(total_paragraph, chunks[0]);
    
    // Activity sparkline
    let activity_block = theme
        .create_block("Recent Activity")
        .border_style(theme.secondary_style());
    
    let sparkline_data: Vec<u64> = (0..30)
        .map(|i| ((i * 3 + 5) % 20) as u64)
        .collect();
    
    let sparkline = Sparkline::default()
        .block(activity_block)
        .data(&sparkline_data)
        .style(theme.accent_style())
        .max(20);
    
    frame.render_widget(sparkline, chunks[1]);
    
    // Last sync
    let sync_block = theme
        .create_block("Last Sync")
        .border_style(theme.success_style());
    
    let sync_text = if let Some(last_sync) = state.last_sync {
        vec![
            Line::from(""),
            Line::from(Span::styled(
                last_sync.format("%Y-%m-%d").to_string(),
                theme.success_style(),
            )),
            Line::from(Span::styled(
                last_sync.format("%H:%M:%S").to_string(),
                theme.success_style(),
            )),
            Line::from(""),
            Line::from(Span::styled("Auto-sync enabled", theme.muted_style())),
        ]
    } else {
        vec![
            Line::from(""),
            Line::from(Span::styled("Never synced", theme.warning_style())),
            Line::from(""),
            Line::from(Span::styled("Press 's' to sync", theme.muted_style())),
        ]
    };
    
    let sync_paragraph = Paragraph::new(sync_text)
        .block(sync_block)
        .alignment(Alignment::Center);
    
    frame.render_widget(sync_paragraph, chunks[2]);
}

fn render_recent_conversations(frame: &mut Frame, area: Rect, state: &AppState, theme: &Theme) {
    let block = theme
        .create_block("Recent Conversations")
        .border_style(theme.border_style());
    
    let items: Vec<ListItem> = state
        .recent_conversations
        .iter()
        .enumerate()
        .map(|(i, conv)| {
            // Highlight selected item with different style
            let is_selected = i == state.home_selected_index;
            let title_style = if is_selected {
                theme.primary_style().add_modifier(Modifier::BOLD | Modifier::UNDERLINED)
            } else {
                theme.primary_style()
            };
            
            let title = Span::styled(&conv.title, title_style);
            let project = Span::styled(
                format!(" [{}]", conv.project),
                theme.secondary_style(),
            );
            let date = Span::styled(
                format!(" - {}", conv.updated_at.format("%Y-%m-%d %H:%M")),
                theme.muted_style(),
            );
            let messages = Span::styled(
                format!(" ({} messages)", conv.message_count),
                theme.muted_style(),
            );
            
            ListItem::new(Line::from(vec![title, project, date, messages]))
        })
        .collect();
    
    let list = List::new(items)
        .block(block)
        .style(theme.base_style())
        .highlight_style(theme.selection_style())
        .highlight_symbol("> ");
    
    // Use stateful widget to show selection
    let mut list_state = ratatui::widgets::ListState::default();
    list_state.select(Some(state.home_selected_index));
    
    frame.render_stateful_widget(list, area, &mut list_state);
}

fn render_quick_actions(frame: &mut Frame, area: Rect, theme: &Theme) {
    let actions = vec![
        ("2", "Browse", "Navigate files"),
        ("3", "Search", "Find conversations"),
        ("4", "Export", "Export selected"),
        ("5", "Stats", "View statistics"),
        ("s", "Sync", "Sync now"),
        ("?", "Help", "Show help"),
    ];
    
    let spans: Vec<Span> = actions
        .iter()
        .flat_map(|(key, action, desc)| {
            vec![
                Span::styled(format!("[{}]", key), theme.accent_style()),
                Span::styled(format!(" {} ", action), theme.primary_style()),
                Span::styled(format!("{}  ", desc), theme.muted_style()),
            ]
        })
        .collect();
    
    let paragraph = Paragraph::new(Line::from(spans))
        .block(Block::default().borders(Borders::TOP).border_style(theme.border_style()))
        .alignment(Alignment::Center);
    
    frame.render_widget(paragraph, area);
}

pub fn handle_key(key: KeyEvent, state: &AppState) -> Option<Action> {
    match (key.modifiers, key.code) {
        // Arrow keys to navigate selection in recent conversations
        (KeyModifiers::NONE, KeyCode::Up) | (KeyModifiers::NONE, KeyCode::Char('k')) => {
            if state.home_selected_index > 0 {
                Some(Action::HomeSelectPrevious)
            } else {
                None
            }
        }
        (KeyModifiers::NONE, KeyCode::Down) | (KeyModifiers::NONE, KeyCode::Char('j')) => {
            if state.home_selected_index < state.recent_conversations.len().saturating_sub(1) {
                Some(Action::HomeSelectNext)
            } else {
                None
            }
        }
        
        // Enter to open selected conversation
        (KeyModifiers::NONE, KeyCode::Enter) => {
            if let Some(conv) = state.recent_conversations.get(state.home_selected_index) {
                Some(Action::OpenConversation(conv.path.clone()))
            } else {
                None
            }
        }
        
        // Refresh actions
        (KeyModifiers::NONE, KeyCode::Char('r')) => Some(Action::RefreshStatistics),
        _ => None,
    }
}
use crate::{state::AppState, ui::theme::Theme};
use chrono::Local;
use ratatui::{
    layout::{Alignment, Rect},
    style::Modifier,
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph},
    Frame,
};

pub fn render(frame: &mut Frame, area: Rect, state: &AppState, theme: &Theme) {
    let mut spans = Vec::new();
    
    // Left side - stats
    spans.push(Span::styled(
        format!(" {} conversations ", state.total_conversations),
        theme.primary_style(),
    ));
    
    spans.push(Span::styled(" | ", theme.border_style()));
    
    spans.push(Span::styled(
        format!(" {:.1} MB ", state.total_size as f64 / 1_048_576.0),
        theme.secondary_style(),
    ));
    
    // Center - current status
    if !state.selected_conversations.is_empty() {
        spans.push(Span::styled(" | ", theme.border_style()));
        spans.push(Span::styled(
            format!(" {} selected ", state.selected_conversations.len()),
            theme.accent_style().add_modifier(Modifier::BOLD),
        ));
    }
    
    // Export queue status
    if !state.export_queue.is_empty() {
        spans.push(Span::styled(" | ", theme.border_style()));
        spans.push(Span::styled(
            format!(" {} exports pending ", state.export_queue.len()),
            theme.warning_style(),
        ));
    }
    
    // Right side - time and help
    spans.push(Span::styled(" | ", theme.border_style()));
    
    let now = Local::now();
    spans.push(Span::styled(
        format!(" {} ", now.format("%H:%M:%S")),
        theme.muted_style(),
    ));
    
    spans.push(Span::styled(" | ", theme.border_style()));
    
    spans.push(Span::styled(
        " [?] Help | [Ctrl+Q] Quit ",
        theme.muted_style(),
    ));
    
    let paragraph = Paragraph::new(Line::from(spans))
        .block(
            Block::default()
                .borders(Borders::TOP)
                .border_style(theme.border_style()),
        )
        .alignment(Alignment::Left);
    
    frame.render_widget(paragraph, area);
}
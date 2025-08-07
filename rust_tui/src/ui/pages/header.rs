use crate::{state::{AppState, Page}, ui::theme::Theme, VERSION};
use ratatui::{
    layout::{Alignment, Rect},
    style::Modifier,
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph},
    Frame,
};

pub fn render(frame: &mut Frame, area: Rect, state: &AppState, theme: &Theme) {
    let pages = vec![
        ("1", "Home", Page::Home),
        ("2", "Browser", Page::Browser),
        ("3", "Search", Page::Search),
        ("4", "Export", Page::Export),
        ("5", "Stats", Page::Statistics),
        ("6", "Settings", Page::Settings),
    ];
    
    let mut spans = vec![
        Span::styled("Claude TUI ", theme.primary_style().add_modifier(Modifier::BOLD)),
        Span::styled(format!("v{} ", VERSION), theme.muted_style()),
        Span::styled(" | ", theme.border_style()),
    ];
    
    for (key, name, page) in pages {
        let is_current = state.current_page == page;
        
        let style = if is_current {
            theme.accent_style().add_modifier(Modifier::BOLD | Modifier::UNDERLINED)
        } else {
            theme.secondary_style()
        };
        
        spans.push(Span::styled(format!("[{}]", key), theme.muted_style()));
        spans.push(Span::styled(format!(" {} ", name), style));
    }
    
    spans.push(Span::styled(" | ", theme.border_style()));
    spans.push(Span::styled(
        format!(" Theme: {} ", theme.name),
        theme.muted_style(),
    ));
    
    let paragraph = Paragraph::new(Line::from(spans))
        .block(
            Block::default()
                .borders(Borders::BOTTOM)
                .border_style(theme.border_style()),
        )
        .alignment(Alignment::Center);
    
    frame.render_widget(paragraph, area);
}
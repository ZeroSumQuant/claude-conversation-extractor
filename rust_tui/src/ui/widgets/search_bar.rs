use crate::ui::theme::Theme;
use ratatui::{
    buffer::Buffer,
    layout::Rect,
    style::Modifier,
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph, Widget},
};

pub struct SearchBarWidget<'a> {
    query: &'a str,
    theme: &'a Theme,
    placeholder: Option<&'a str>,
    show_history: bool,
}

impl<'a> SearchBarWidget<'a> {
    pub fn new(query: &'a str, theme: &'a Theme) -> Self {
        Self {
            query,
            theme,
            placeholder: None,
            show_history: false,
        }
    }
    
    pub fn placeholder(mut self, placeholder: &'a str) -> Self {
        self.placeholder = Some(placeholder);
        self
    }
    
    pub fn show_history(mut self, show: bool) -> Self {
        self.show_history = show;
        self
    }
}

impl<'a> Widget for SearchBarWidget<'a> {
    fn render(self, area: Rect, buf: &mut Buffer) {
        let block = Block::default()
            .borders(Borders::ALL)
            .border_style(self.theme.accent_style())
            .title("Search")
            .title_style(self.theme.title_style());
        
        let mut spans = vec![
            Span::styled("🔍 ", self.theme.accent_style()),
        ];
        
        if self.query.is_empty() {
            if let Some(placeholder) = self.placeholder {
                spans.push(Span::styled(
                    placeholder,
                    self.theme.muted_style().add_modifier(Modifier::ITALIC),
                ));
            }
        } else {
            spans.push(Span::styled(self.query, self.theme.foreground));
        }
        
        // Add cursor
        spans.push(Span::styled("█", self.theme.accent_style()));
        
        // Add history indicator
        if self.show_history {
            spans.push(Span::styled(
                "  [↑↓ history]",
                self.theme.muted_style(),
            ));
        }
        
        let paragraph = Paragraph::new(Line::from(spans))
            .block(block);
        
        paragraph.render(area, buf);
    }
}
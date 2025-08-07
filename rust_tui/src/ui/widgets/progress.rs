use crate::ui::theme::Theme;
use ratatui::{
    buffer::Buffer,
    layout::Rect,
    style::Modifier,
    text::{Line, Span},
    widgets::{Block, Borders, Gauge, Widget},
};

pub struct ProgressWidget<'a> {
    current: usize,
    total: usize,
    message: &'a str,
    theme: &'a Theme,
}

impl<'a> ProgressWidget<'a> {
    pub fn new(current: usize, total: usize, message: &'a str, theme: &'a Theme) -> Self {
        Self {
            current,
            total,
            message,
            theme,
        }
    }
}

impl<'a> Widget for ProgressWidget<'a> {
    fn render(self, area: Rect, buf: &mut Buffer) {
        let progress = if self.total > 0 {
            (self.current as f64 / self.total as f64 * 100.0) as u16
        } else {
            0
        };
        
        let label = format!(
            "{}/{} - {}",
            self.current, self.total, self.message
        );
        
        let gauge = Gauge::default()
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_style(self.theme.border_style())
                    .title("Progress")
                    .title_style(self.theme.title_style()),
            )
            .gauge_style(self.theme.accent_style())
            .percent(progress.min(100))
            .label(label);
        
        gauge.render(area, buf);
    }
}
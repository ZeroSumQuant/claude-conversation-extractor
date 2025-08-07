use crate::{
    state::{Notification, NotificationLevel},
    ui::theme::Theme,
};
use ratatui::{
    buffer::Buffer,
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::Modifier,
    text::{Line, Span},
    widgets::{Block, Borders, Clear, Paragraph, Widget, Wrap},
};
use std::collections::VecDeque;

pub struct NotificationWidget<'a> {
    notifications: &'a VecDeque<Notification>,
    theme: &'a Theme,
}

impl<'a> NotificationWidget<'a> {
    pub fn new(notifications: &'a VecDeque<Notification>, theme: &'a Theme) -> Self {
        Self {
            notifications,
            theme,
        }
    }
}

impl<'a> Widget for NotificationWidget<'a> {
    fn render(self, area: Rect, buf: &mut Buffer) {
        if self.notifications.is_empty() {
            return;
        }
        
        // Position notifications in the top-right corner
        let notification_width = 40.min(area.width - 2);
        let notification_height = 3;
        let x = area.width.saturating_sub(notification_width + 1);
        let y = 3; // Below the header
        
        // Render up to 3 most recent notifications
        for (index, notification) in self.notifications.iter().take(3).enumerate() {
            let notification_area = Rect::new(
                x,
                y + (index as u16 * (notification_height + 1)),
                notification_width,
                notification_height,
            );
            
            // Clear the background
            Clear.render(notification_area, buf);
            
            // Choose style based on notification level
            let (border_style, icon) = match notification.level {
                NotificationLevel::Info => (self.theme.primary_style(), "ℹ "),
                NotificationLevel::Success => (self.theme.success_style(), "✓ "),
                NotificationLevel::Warning => (self.theme.warning_style(), "⚠ "),
                NotificationLevel::Error => (self.theme.error_style(), "✗ "),
            };
            
            let block = Block::default()
                .borders(Borders::ALL)
                .border_style(border_style);
            
            let content = Line::from(vec![
                Span::styled(icon, border_style.add_modifier(Modifier::BOLD)),
                Span::styled(&notification.message, self.theme.foreground),
            ]);
            
            let paragraph = Paragraph::new(content)
                .block(block)
                .alignment(Alignment::Left)
                .wrap(Wrap { trim: true });
            
            paragraph.render(notification_area, buf);
        }
    }
}
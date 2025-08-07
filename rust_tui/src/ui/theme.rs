use anyhow::Result;
use ratatui::{
    layout::Rect,
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders},
    Frame,
};

#[derive(Debug, Clone)]
pub struct Theme {
    pub name: String,
    pub background: Color,
    pub foreground: Color,
    pub primary: Color,
    pub secondary: Color,
    pub accent: Color,
    pub success: Color,
    pub warning: Color,
    pub error: Color,
    pub border: Color,
    pub highlight: Color,
    pub muted: Color,
    pub selection: Color,
}

impl Theme {
    pub fn from_name(name: &str) -> Result<Self> {
        match name.to_lowercase().as_str() {
            "matrix" => Ok(Self::matrix()),
            "claude" => Ok(Self::claude()),
            "cyberpunk" => Ok(Self::cyberpunk()),
            _ => Ok(Self::claude()),
        }
    }
    
    pub fn matrix() -> Self {
        Self {
            name: "Matrix".to_string(),
            background: Color::Black,
            foreground: Color::Rgb(0, 255, 0),
            primary: Color::Rgb(0, 255, 0),
            secondary: Color::Rgb(0, 200, 0),
            accent: Color::Rgb(50, 255, 50),
            success: Color::Rgb(0, 255, 0),
            warning: Color::Rgb(255, 255, 0),
            error: Color::Rgb(255, 0, 0),
            border: Color::Rgb(0, 150, 0),
            highlight: Color::Rgb(0, 255, 0),
            muted: Color::Rgb(0, 100, 0),
            selection: Color::Rgb(0, 50, 0),
        }
    }
    
    pub fn claude() -> Self {
        Self {
            name: "Claude".to_string(),
            background: Color::Rgb(25, 25, 35),
            foreground: Color::Rgb(230, 230, 245),
            primary: Color::Rgb(147, 112, 219),    // Medium purple
            secondary: Color::Rgb(186, 165, 219),   // Lavender
            accent: Color::Rgb(255, 182, 193),      // Light pink
            success: Color::Rgb(144, 238, 144),     // Light green
            warning: Color::Rgb(255, 218, 185),     // Peach
            error: Color::Rgb(255, 99, 71),         // Tomato
            border: Color::Rgb(100, 100, 130),
            highlight: Color::Rgb(221, 160, 221),   // Plum
            muted: Color::Rgb(128, 128, 150),
            selection: Color::Rgb(75, 0, 130),      // Indigo
        }
    }
    
    pub fn cyberpunk() -> Self {
        Self {
            name: "Cyberpunk".to_string(),
            background: Color::Rgb(15, 0, 30),
            foreground: Color::Rgb(255, 255, 255),
            primary: Color::Rgb(255, 0, 255),       // Magenta
            secondary: Color::Rgb(0, 255, 255),     // Cyan
            accent: Color::Rgb(255, 20, 147),       // Deep pink
            success: Color::Rgb(0, 255, 127),       // Spring green
            warning: Color::Rgb(255, 165, 0),       // Orange
            error: Color::Rgb(255, 0, 128),         // Rose
            border: Color::Rgb(128, 0, 128),        // Purple
            highlight: Color::Rgb(255, 105, 180),   // Hot pink
            muted: Color::Rgb(75, 0, 130),          // Indigo
            selection: Color::Rgb(138, 43, 226),    // Blue violet
        }
    }
    
    // Style helpers
    pub fn base_style(&self) -> Style {
        Style::default()
            .fg(self.foreground)
            .bg(self.background)
    }
    
    pub fn primary_style(&self) -> Style {
        Style::default().fg(self.primary)
    }
    
    pub fn secondary_style(&self) -> Style {
        Style::default().fg(self.secondary)
    }
    
    pub fn accent_style(&self) -> Style {
        Style::default().fg(self.accent)
    }
    
    pub fn success_style(&self) -> Style {
        Style::default().fg(self.success)
    }
    
    pub fn warning_style(&self) -> Style {
        Style::default().fg(self.warning)
    }
    
    pub fn error_style(&self) -> Style {
        Style::default().fg(self.error)
    }
    
    pub fn border_style(&self) -> Style {
        Style::default().fg(self.border)
    }
    
    pub fn highlight_style(&self) -> Style {
        Style::default()
            .fg(self.highlight)
            .add_modifier(Modifier::BOLD)
    }
    
    pub fn muted_style(&self) -> Style {
        Style::default().fg(self.muted)
    }
    
    pub fn selection_style(&self) -> Style {
        Style::default()
            .bg(self.selection)
            .add_modifier(Modifier::BOLD)
    }
    
    pub fn title_style(&self) -> Style {
        Style::default()
            .fg(self.primary)
            .add_modifier(Modifier::BOLD)
    }
    
    pub fn draw_background(&self, frame: &mut Frame, area: Rect) {
        let block = Block::default()
            .style(self.base_style());
        frame.render_widget(block, area);
    }
    
    pub fn create_block<'a>(&self, title: &'a str) -> Block<'a> {
        Block::default()
            .title(title)
            .borders(Borders::ALL)
            .border_style(self.border_style())
            .title_style(self.title_style())
    }
    
    pub fn create_highlight_block<'a>(&self, title: &'a str) -> Block<'a> {
        Block::default()
            .title(title)
            .borders(Borders::ALL)
            .border_style(self.highlight_style())
            .title_style(self.highlight_style())
    }
}
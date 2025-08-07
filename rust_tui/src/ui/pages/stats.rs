use crate::{state::AppState, ui::theme::Theme};
use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::Modifier,
    symbols,
    text::{Line, Span},
    widgets::{Axis, BarChart, Block, Borders, Chart, Dataset, GraphType, Paragraph},
    Frame,
};

pub fn render(frame: &mut Frame, area: Rect, state: &AppState, theme: &Theme) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Percentage(40),  // Time series chart
            Constraint::Percentage(30),  // Bar charts
            Constraint::Percentage(30),  // Summary stats
        ])
        .split(area);
    
    render_activity_chart(frame, chunks[0], state, theme);
    render_distribution_charts(frame, chunks[1], state, theme);
    render_summary_stats(frame, chunks[2], state, theme);
}

fn render_activity_chart(frame: &mut Frame, area: Rect, state: &AppState, theme: &Theme) {
    let block = theme
        .create_block("Conversation Activity (Last 30 Days)")
        .border_style(theme.primary_style());
    
    // Generate sample data for demonstration
    let data: Vec<(f64, f64)> = (0..30)
        .map(|i| {
            let x = i as f64;
            let y = ((i as f64 * 0.3).sin() * 10.0 + 15.0 + (i % 7) as f64).max(0.0);
            (x, y)
        })
        .collect();
    
    let datasets = vec![Dataset::default()
        .name("Conversations")
        .marker(symbols::Marker::Braille)
        .style(theme.accent_style())
        .graph_type(GraphType::Line)
        .data(&data)];
    
    let x_labels = vec![
        Span::raw("30d ago"),
        Span::raw("15d ago"),
        Span::raw("Today"),
    ];
    
    let chart = Chart::new(datasets)
        .block(block)
        .x_axis(
            Axis::default()
                .title("Date")
                .style(theme.muted_style())
                .labels(x_labels)
                .bounds([0.0, 30.0]),
        )
        .y_axis(
            Axis::default()
                .title("Count")
                .style(theme.muted_style())
                .labels(vec![Span::raw("0"), Span::raw("15"), Span::raw("30")])
                .bounds([0.0, 30.0]),
        );
    
    frame.render_widget(chart, area);
}

fn render_distribution_charts(frame: &mut Frame, area: Rect, state: &AppState, theme: &Theme) {
    let chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
        .split(area);
    
    // Conversations by project
    render_project_distribution(frame, chunks[0], state, theme);
    
    // Message count distribution
    render_message_distribution(frame, chunks[1], state, theme);
}

fn render_project_distribution(frame: &mut Frame, area: Rect, state: &AppState, theme: &Theme) {
    let block = theme
        .create_block("By Project")
        .border_style(theme.secondary_style());
    
    // Sample data
    let data = vec![
        ("Project A", 45),
        ("Project B", 32),
        ("Project C", 28),
        ("Project D", 15),
        ("Other", 8),
    ];
    
    let bar_data: Vec<(&str, u64)> = data
        .iter()
        .map(|(label, value)| (*label, *value as u64))
        .collect();
    
    let barchart = BarChart::default()
        .block(block)
        .data(&bar_data)
        .bar_width(5)
        .bar_gap(2)
        .bar_style(theme.accent_style())
        .value_style(theme.primary_style().add_modifier(Modifier::BOLD));
    
    frame.render_widget(barchart, area);
}

fn render_message_distribution(frame: &mut Frame, area: Rect, _state: &AppState, theme: &Theme) {
    let block = theme
        .create_block("Message Count")
        .border_style(theme.secondary_style());
    
    // Sample data
    let data = vec![
        ("1-10", 120),
        ("11-50", 85),
        ("51-100", 45),
        ("100+", 22),
    ];
    
    let bar_data: Vec<(&str, u64)> = data
        .iter()
        .map(|(label, value)| (*label, *value as u64))
        .collect();
    
    let barchart = BarChart::default()
        .block(block)
        .data(&bar_data)
        .bar_width(7)
        .bar_gap(2)
        .bar_style(theme.primary_style())
        .value_style(theme.accent_style().add_modifier(Modifier::BOLD));
    
    frame.render_widget(barchart, area);
}

fn render_summary_stats(frame: &mut Frame, area: Rect, state: &AppState, theme: &Theme) {
    let block = theme
        .create_block("Summary Statistics")
        .border_style(theme.border_style());
    
    let chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage(25),
            Constraint::Percentage(25),
            Constraint::Percentage(25),
            Constraint::Percentage(25),
        ])
        .split(area);
    
    // Total conversations
    render_stat_box(
        frame,
        chunks[0],
        "Total",
        &state.total_conversations.to_string(),
        "conversations",
        theme.primary_style(),
        theme,
    );
    
    // Average per day
    render_stat_box(
        frame,
        chunks[1],
        "Avg/Day",
        "8.5",
        "last 30 days",
        theme.secondary_style(),
        theme,
    );
    
    // Storage used
    render_stat_box(
        frame,
        chunks[2],
        "Storage",
        &format!("{:.1} MB", state.total_size as f64 / 1_048_576.0),
        "total size",
        theme.accent_style(),
        theme,
    );
    
    // Growth rate
    render_stat_box(
        frame,
        chunks[3],
        "Growth",
        "+12%",
        "this month",
        theme.success_style(),
        theme,
    );
}

fn render_stat_box(
    frame: &mut Frame,
    area: Rect,
    title: &str,
    value: &str,
    subtitle: &str,
    value_style: ratatui::style::Style,
    theme: &Theme,
) {
    let paragraph = Paragraph::new(vec![
        Line::from(Span::styled(title, theme.muted_style())),
        Line::from(Span::styled(
            value,
            value_style.add_modifier(Modifier::BOLD),
        )),
        Line::from(Span::styled(subtitle, theme.muted_style())),
    ])
    .alignment(Alignment::Center);
    
    frame.render_widget(paragraph, area);
}

pub fn handle_key(_key: KeyEvent, _state: &AppState) -> Option<crate::state::Action> {
    // Statistics page is mostly read-only
    // Could add export functionality here
    None
}
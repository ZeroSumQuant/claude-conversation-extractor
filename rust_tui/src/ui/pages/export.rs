use crate::{
    state::{Action, AppState, ExportFormat, ExportStatus},
    ui::theme::Theme,
};
use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::Modifier,
    text::{Line, Span},
    widgets::{Block, Borders, Gauge, List, ListItem, Paragraph},
    Frame,
};

pub fn render(frame: &mut Frame, area: Rect, state: &mut AppState, theme: &Theme) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(8),   // Export options
            Constraint::Min(10),     // Selected items / Queue
            Constraint::Length(5),   // Progress
            Constraint::Length(3),   // Actions
        ])
        .split(area);
    
    render_export_options(frame, chunks[0], state, theme);
    render_export_queue(frame, chunks[1], state, theme);
    render_progress(frame, chunks[2], state, theme);
    render_actions(frame, chunks[3], theme);
}

fn render_export_options(frame: &mut Frame, area: Rect, state: &AppState, theme: &Theme) {
    let block = theme
        .create_block("Export Options")
        .border_style(theme.primary_style());
    
    let format_options = vec![
        ("Markdown", ExportFormat::Markdown),
        ("JSON", ExportFormat::Json),
        ("HTML", ExportFormat::Html),
        ("PDF", ExportFormat::Pdf),
        ("ZIP", ExportFormat::Zip),
    ];
    
    let format_line = Line::from(
        format_options
            .iter()
            .map(|(name, format)| {
                let selected = state.export_format == *format;
                let style = if selected {
                    theme.accent_style().add_modifier(Modifier::BOLD)
                } else {
                    theme.muted_style()
                };
                Span::styled(
                    format!(" [{}] {}  ", if selected { "•" } else { " " }, name),
                    style,
                )
            })
            .collect::<Vec<_>>(),
    );
    
    let path_line = Line::from(vec![
        Span::styled("Path: ", theme.muted_style()),
        Span::styled(
            state.export_path.to_string_lossy().to_string(),
            theme.secondary_style(),
        ),
    ]);
    
    let count_line = Line::from(vec![
        Span::styled("Selected: ", theme.muted_style()),
        Span::styled(
            format!("{} conversations", state.selected_conversations.len()),
            if state.selected_conversations.is_empty() {
                theme.warning_style()
            } else {
                theme.success_style()
            },
        ),
    ]);
    
    let paragraph = Paragraph::new(vec![
        Line::from(""),
        format_line,
        Line::from(""),
        path_line,
        count_line,
        Line::from(""),
    ])
    .block(block);
    
    frame.render_widget(paragraph, area);
}

fn render_export_queue(frame: &mut Frame, area: Rect, state: &AppState, theme: &Theme) {
    let title = format!("Export Queue ({})", state.export_queue.len());
    let block = theme
        .create_block(&title)
        .border_style(theme.secondary_style());
    
    if state.export_queue.is_empty() && state.selected_conversations.is_empty() {
        let paragraph = Paragraph::new(vec![
            Line::from(""),
            Line::from(Span::styled(
                "No conversations selected for export",
                theme.muted_style(),
            )),
            Line::from(""),
            Line::from(Span::styled(
                "Select conversations from Browser or Search pages",
                theme.muted_style(),
            )),
            Line::from(Span::styled(
                "Use [Space] to select multiple items",
                theme.muted_style(),
            )),
        ])
        .block(block)
        .alignment(Alignment::Center);
        
        frame.render_widget(paragraph, area);
    } else {
        let items: Vec<ListItem> = state
            .export_queue
            .iter()
            .map(|job| {
                let status_span = match &job.status {
                    ExportStatus::Pending => {
                        Span::styled("[Pending]", theme.muted_style())
                    }
                    ExportStatus::InProgress(progress) => {
                        Span::styled(
                            format!("[{:.0}%]", progress * 100.0),
                            theme.warning_style(),
                        )
                    }
                    ExportStatus::Completed => {
                        Span::styled("[Done]", theme.success_style())
                    }
                    ExportStatus::Failed(err) => {
                        Span::styled(format!("[Failed: {}]", err), theme.error_style())
                    }
                };
                
                let format_span = Span::styled(
                    format!(" {} ", format_name(job.format)),
                    theme.secondary_style(),
                );
                
                let count_span = Span::styled(
                    format!("({} items)", job.conversations.len()),
                    theme.muted_style(),
                );
                
                ListItem::new(Line::from(vec![status_span, format_span, count_span]))
            })
            .collect();
        
        let list = List::new(items)
            .block(block)
            .style(theme.base_style())
            .highlight_style(theme.selection_style())
            .highlight_symbol("> ");
        
        frame.render_widget(list, area);
    }
}

fn render_progress(frame: &mut Frame, area: Rect, state: &AppState, theme: &Theme) {
    let block = theme
        .create_block("Progress")
        .border_style(theme.border_style());
    
    if let Some(progress) = &state.export_progress {
        let ratio = progress.current as f64 / progress.total as f64;
        
        let gauge = Gauge::default()
            .block(block)
            .gauge_style(theme.accent_style())
            .percent((ratio * 100.0) as u16)
            .label(format!(
                "{}/{} - {}",
                progress.current, progress.total, progress.message
            ));
        
        frame.render_widget(gauge, area);
    } else {
        let paragraph = Paragraph::new(vec![
            Line::from(""),
            Line::from(Span::styled("No export in progress", theme.muted_style())),
        ])
        .block(block)
        .alignment(Alignment::Center);
        
        frame.render_widget(paragraph, area);
    }
}

fn render_actions(frame: &mut Frame, area: Rect, theme: &Theme) {
    let actions = vec![
        ("e", "Start Export"),
        ("f", "Change Format"),
        ("p", "Change Path"),
        ("c", "Clear Queue"),
        ("Space", "Select Items"),
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

fn format_name(format: ExportFormat) -> &'static str {
    match format {
        ExportFormat::Markdown => "Markdown",
        ExportFormat::Json => "JSON",
        ExportFormat::Html => "HTML",
        ExportFormat::Pdf => "PDF",
        ExportFormat::Zip => "ZIP Archive",
    }
}

pub fn handle_key(key: KeyEvent, state: &AppState) -> Option<Action> {
    match (key.modifiers, key.code) {
        // Start export
        (KeyModifiers::NONE, KeyCode::Char('e')) => {
            if !state.selected_conversations.is_empty() {
                Some(Action::StartExport)
            } else {
                Some(Action::ShowNotification(
                    "No conversations selected for export".to_string(),
                    crate::state::NotificationLevel::Warning,
                ))
            }
        }
        // Change format
        (KeyModifiers::NONE, KeyCode::Char('f')) => {
            let next_format = match state.export_format {
                ExportFormat::Markdown => ExportFormat::Json,
                ExportFormat::Json => ExportFormat::Html,
                ExportFormat::Html => ExportFormat::Pdf,
                ExportFormat::Pdf => ExportFormat::Zip,
                ExportFormat::Zip => ExportFormat::Markdown,
            };
            Some(Action::SetExportFormat(next_format))
        }
        // Change path
        (KeyModifiers::NONE, KeyCode::Char('p')) => {
            Some(Action::ShowInput(
                "Export Path".to_string(),
                "Enter export directory:".to_string(),
                Box::new(Action::SetExportPath(state.export_path.clone())),
            ))
        }
        // Clear queue
        (KeyModifiers::NONE, KeyCode::Char('c')) => Some(Action::ClearExportQueue),
        _ => None,
    }
}
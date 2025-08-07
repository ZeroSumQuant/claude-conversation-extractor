use crate::{state::Modal, ui::theme::Theme};
use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::Modifier,
    text::{Line, Span},
    widgets::{Block, Borders, Clear, List, ListItem, Paragraph, Wrap},
    Frame,
};

pub fn render(frame: &mut Frame, area: Rect, modal: &Modal, theme: &Theme) {
    // Calculate modal size and position
    let modal_area = centered_rect(60, 40, area);
    
    // Clear the background
    frame.render_widget(Clear, modal_area);
    
    match modal {
        Modal::Confirm {
            title,
            message,
            on_confirm: _,
            on_cancel: _,
        } => render_confirm_modal(frame, modal_area, title, message, theme),
        
        Modal::Input {
            title,
            prompt,
            value,
            on_submit: _,
            on_cancel: _,
        } => render_input_modal(frame, modal_area, title, prompt, value, theme),
        
        Modal::Help => render_help_modal(frame, modal_area, theme),
        
        Modal::CommandPalette {
            query,
            commands,
            selected_index,
        } => render_command_palette(frame, modal_area, query, commands, *selected_index, theme),
    }
}

fn render_confirm_modal(
    frame: &mut Frame,
    area: Rect,
    title: &str,
    message: &str,
    theme: &Theme,
) {
    let block = theme
        .create_highlight_block(title)
        .border_style(theme.warning_style());
    
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Min(3),
            Constraint::Length(3),
        ])
        .split(area);
    
    let message_paragraph = Paragraph::new(vec![
        Line::from(""),
        Line::from(Span::styled(message, theme.foreground)),
        Line::from(""),
    ])
    .block(block)
    .alignment(Alignment::Center)
    .wrap(Wrap { trim: true });
    
    frame.render_widget(message_paragraph, chunks[0]);
    
    let actions = Line::from(vec![
        Span::styled("[Y]", theme.success_style().add_modifier(Modifier::BOLD)),
        Span::styled(" Confirm  ", theme.foreground),
        Span::styled("[N]", theme.error_style().add_modifier(Modifier::BOLD)),
        Span::styled(" Cancel", theme.foreground),
    ]);
    
    let actions_paragraph = Paragraph::new(actions)
        .block(
            Block::default()
                .borders(Borders::TOP)
                .border_style(theme.border_style()),
        )
        .alignment(Alignment::Center);
    
    frame.render_widget(actions_paragraph, chunks[1]);
}

fn render_input_modal(
    frame: &mut Frame,
    area: Rect,
    title: &str,
    prompt: &str,
    value: &str,
    theme: &Theme,
) {
    let block = theme
        .create_highlight_block(title)
        .border_style(theme.primary_style());
    
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Length(3),
            Constraint::Length(3),
        ])
        .split(area);
    
    let prompt_paragraph = Paragraph::new(Line::from(Span::styled(prompt, theme.secondary_style())))
        .block(block)
        .alignment(Alignment::Left);
    
    frame.render_widget(prompt_paragraph, chunks[0]);
    
    let input_block = Block::default()
        .borders(Borders::ALL)
        .border_style(theme.accent_style());
    
    let input_paragraph = Paragraph::new(Line::from(vec![
        Span::styled(value, theme.foreground),
        Span::styled("█", theme.accent_style()), // Cursor
    ]))
    .block(input_block);
    
    frame.render_widget(input_paragraph, chunks[1]);
    
    let actions = Line::from(vec![
        Span::styled("[Enter]", theme.success_style()),
        Span::styled(" Submit  ", theme.foreground),
        Span::styled("[ESC]", theme.error_style()),
        Span::styled(" Cancel", theme.foreground),
    ]);
    
    let actions_paragraph = Paragraph::new(actions)
        .alignment(Alignment::Center);
    
    frame.render_widget(actions_paragraph, chunks[2]);
}

fn render_help_modal(frame: &mut Frame, area: Rect, theme: &Theme) {
    let block = theme
        .create_highlight_block("Help")
        .border_style(theme.primary_style());
    
    let help_items = vec![
        ("Navigation", vec![
            ("1-6", "Switch between pages"),
            ("Tab", "Next page"),
            ("Shift+Tab", "Previous page"),
            ("↑/↓, j/k", "Move selection up/down"),
            ("←/→, h/l", "Expand/collapse in browser"),
            ("PgUp/PgDn", "Scroll page"),
        ]),
        ("Actions", vec![
            ("Enter", "Select/Open"),
            ("Space", "Toggle selection"),
            ("/", "Open command palette"),
            ("?", "Show this help"),
            ("Ctrl+Q", "Quit application"),
            ("Ctrl+T", "Cycle themes"),
        ]),
        ("Search", vec![
            ("Type", "Enter search query"),
            ("Enter", "Execute search"),
            ("Ctrl+L", "Clear search"),
            ("Ctrl+R", "Toggle regex mode"),
            ("Tab", "Focus filters"),
        ]),
        ("Export", vec![
            ("e", "Start export"),
            ("f", "Change format"),
            ("p", "Change path"),
            ("c", "Clear queue"),
        ]),
    ];
    
    let mut lines = Vec::new();
    
    for (section, items) in help_items {
        lines.push(Line::from(Span::styled(
            section,
            theme.accent_style().add_modifier(Modifier::BOLD),
        )));
        lines.push(Line::from(""));
        
        for (key, desc) in items {
            lines.push(Line::from(vec![
                Span::styled(format!("  {:12}", key), theme.primary_style()),
                Span::styled(desc, theme.secondary_style()),
            ]));
        }
        
        lines.push(Line::from(""));
    }
    
    lines.push(Line::from(Span::styled(
        "Press ESC or ? to close",
        theme.muted_style(),
    )));
    
    let paragraph = Paragraph::new(lines)
        .block(block)
        .alignment(Alignment::Left)
        .wrap(Wrap { trim: true });
    
    frame.render_widget(paragraph, area);
}

fn render_command_palette(
    frame: &mut Frame,
    area: Rect,
    query: &str,
    commands: &[crate::state::Command],
    selected_index: usize,
    theme: &Theme,
) {
    let block = theme
        .create_highlight_block("Command Palette")
        .border_style(theme.accent_style());
    
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(5),
        ])
        .split(area);
    
    // Search input
    let input_block = Block::default()
        .borders(Borders::BOTTOM)
        .border_style(theme.border_style());
    
    let input_paragraph = Paragraph::new(Line::from(vec![
        Span::styled("> ", theme.accent_style()),
        Span::styled(query, theme.foreground),
        Span::styled("█", theme.accent_style()),
    ]))
    .block(input_block);
    
    frame.render_widget(input_paragraph, chunks[0]);
    
    // Commands list
    let items: Vec<ListItem> = commands
        .iter()
        .map(|cmd| {
            let mut spans = vec![
                Span::styled(&cmd.name, theme.primary_style().add_modifier(Modifier::BOLD)),
            ];
            
            if let Some(shortcut) = &cmd.shortcut {
                spans.push(Span::styled(
                    format!(" [{}]", shortcut),
                    theme.muted_style(),
                ));
            }
            
            spans.push(Span::styled(
                format!(" - {}", cmd.description),
                theme.secondary_style(),
            ));
            
            ListItem::new(Line::from(spans))
        })
        .collect();
    
    let list = List::new(items)
        .block(block)
        .style(theme.base_style())
        .highlight_style(theme.selection_style())
        .highlight_symbol("> ");
    
    let mut list_state = ratatui::widgets::ListState::default();
    list_state.select(Some(selected_index));
    frame.render_stateful_widget(list, chunks[1], &mut list_state);
}

fn centered_rect(percent_x: u16, percent_y: u16, area: Rect) -> Rect {
    let popup_layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Percentage((100 - percent_y) / 2),
            Constraint::Percentage(percent_y),
            Constraint::Percentage((100 - percent_y) / 2),
        ])
        .split(area);
    
    Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage((100 - percent_x) / 2),
            Constraint::Percentage(percent_x),
            Constraint::Percentage((100 - percent_x) / 2),
        ])
        .split(popup_layout[1])[1]
}
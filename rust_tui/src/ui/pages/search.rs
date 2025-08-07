use crate::{
    state::{Action, AppState, SearchResult},
    ui::{theme::Theme, widgets::SearchBarWidget},
};
use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::Modifier,
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem, Paragraph},
    Frame,
};

pub fn render(frame: &mut Frame, area: Rect, state: &mut AppState, theme: &Theme) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),   // Search bar
            Constraint::Length(3),   // Filters
            Constraint::Min(10),     // Results
            Constraint::Length(3),   // Status
        ])
        .split(area);
    
    render_search_bar(frame, chunks[0], state, theme);
    render_filters(frame, chunks[1], state, theme);
    render_results(frame, chunks[2], state, theme);
    render_search_status(frame, chunks[3], state, theme);
}

fn render_search_bar(frame: &mut Frame, area: Rect, state: &mut AppState, theme: &Theme) {
    let search_bar = SearchBarWidget::new(&state.search_query, theme)
        .placeholder("Search conversations... (regex supported)")
        .show_history(!state.search_history.is_empty());
    
    frame.render_widget(search_bar, area);
}

fn render_filters(frame: &mut Frame, area: Rect, state: &AppState, theme: &Theme) {
    let filters = vec![
        ("Date", state.search_filters.date_from.is_some()),
        ("Project", !state.search_filters.projects.is_empty()),
        ("Tags", !state.search_filters.tags.is_empty()),
        ("Regex", state.search_filters.use_regex),
    ];
    
    let filter_spans: Vec<Span> = filters
        .iter()
        .flat_map(|(name, active)| {
            let style = if *active {
                theme.accent_style()
            } else {
                theme.muted_style()
            };
            vec![
                Span::styled(format!("[{}]", if *active { "x" } else { " " }), style),
                Span::styled(format!(" {}  ", name), style),
            ]
        })
        .collect();
    
    let paragraph = Paragraph::new(Line::from(filter_spans))
        .block(
            Block::default()
                .borders(Borders::BOTTOM)
                .border_style(theme.border_style()),
        )
        .alignment(Alignment::Left);
    
    frame.render_widget(paragraph, area);
}

fn render_results(frame: &mut Frame, area: Rect, state: &mut AppState, theme: &Theme) {
    let title = format!("Results ({})", state.search_results.len());
    let block = theme
        .create_block(&title)
        .border_style(if state.search_results.is_empty() {
            theme.muted_style()
        } else {
            theme.primary_style()
        });
    
    if state.search_results.is_empty() {
        let paragraph = Paragraph::new(vec![
            Line::from(""),
            Line::from(Span::styled(
                if state.search_query.is_empty() {
                    "Enter a search query above"
                } else {
                    "No results found"
                },
                theme.muted_style(),
            )),
            Line::from(""),
            Line::from(Span::styled(
                "Tips: Use regex patterns, try different filters",
                theme.muted_style(),
            )),
        ])
        .block(block)
        .alignment(Alignment::Center);
        
        frame.render_widget(paragraph, area);
    } else {
        let items: Vec<ListItem> = state
            .search_results
            .iter()
            .skip(state.search_scroll_offset)
            .take(area.height as usize - 2)
            .map(|result| render_search_result(result, theme))
            .collect();
        
        let list = List::new(items)
            .block(block)
            .style(theme.base_style())
            .highlight_style(theme.selection_style())
            .highlight_symbol("> ");
        
        let mut list_state = ratatui::widgets::ListState::default();
        list_state.select(Some(state.search_selected_index));
        frame.render_stateful_widget(list, area, &mut list_state);
    }
}

fn render_search_result<'a>(result: &'a SearchResult, theme: &'a Theme) -> ListItem<'a> {
    let title = Span::styled(
        &result.conversation.title,
        theme.primary_style().add_modifier(Modifier::BOLD),
    );
    
    let score = Span::styled(
        format!(" [{:.0}%]", result.score * 100.0),
        if result.score > 0.8 {
            theme.success_style()
        } else if result.score > 0.5 {
            theme.warning_style()
        } else {
            theme.muted_style()
        },
    );
    
    let project = Span::styled(
        format!(" {}", result.conversation.project),
        theme.secondary_style(),
    );
    
    let date = Span::styled(
        format!(" - {}", result.conversation.updated_at.format("%Y-%m-%d")),
        theme.muted_style(),
    );
    
    let messages = Span::styled(
        format!(" ({} msgs)", result.conversation.message_count),
        theme.muted_style(),
    );
    
    let first_line = Line::from(vec![title, score, project, date, messages]);
    
    // Add match preview if available
    let mut lines = vec![first_line];
    
    if let Some(first_match) = result.matches.first() {
        let preview = Span::styled(
            format!("  └─ ...{}...", truncate(&first_match.text, 60)),
            theme.muted_style(),
        );
        lines.push(Line::from(preview));
    }
    
    ListItem::new(lines)
}

fn render_search_status(frame: &mut Frame, area: Rect, state: &AppState, theme: &Theme) {
    let status_text = if !state.search_query.is_empty() {
        format!(
            "Found {} results | Selected: {} | Press Enter to view",
            state.search_results.len(),
            state.search_selected_index + 1
        )
    } else {
        "Type to search | / for regex | Tab for filters | ? for help".to_string()
    };
    
    let paragraph = Paragraph::new(Line::from(Span::styled(status_text, theme.muted_style())))
        .block(
            Block::default()
                .borders(Borders::TOP)
                .border_style(theme.border_style()),
        )
        .alignment(Alignment::Center);
    
    frame.render_widget(paragraph, area);
}

fn truncate(s: &str, max_len: usize) -> String {
    if s.len() <= max_len {
        s.to_string()
    } else {
        format!("{}...", &s[..max_len - 3])
    }
}

pub fn handle_key(key: KeyEvent, state: &AppState) -> Option<Action> {
    match (key.modifiers, key.code) {
        // Text input
        (KeyModifiers::NONE, KeyCode::Char(c)) => {
            let mut query = state.search_query.clone();
            query.push(c);
            Some(Action::UpdateSearchQuery(query))
        }
        (KeyModifiers::NONE, KeyCode::Backspace) => {
            let mut query = state.search_query.clone();
            query.pop();
            Some(Action::UpdateSearchQuery(query))
        }
        (KeyModifiers::NONE, KeyCode::Enter) => {
            if !state.search_query.is_empty() {
                Some(Action::ExecuteSearch)
            } else {
                None
            }
        }
        // Navigation
        (KeyModifiers::NONE, KeyCode::Up) | (KeyModifiers::NONE, KeyCode::Char('k')) => {
            if state.search_selected_index > 0 {
                Some(Action::SelectSearchResult(state.search_selected_index - 1))
            } else {
                None
            }
        }
        (KeyModifiers::NONE, KeyCode::Down) | (KeyModifiers::NONE, KeyCode::Char('j')) => {
            if state.search_selected_index < state.search_results.len().saturating_sub(1) {
                Some(Action::SelectSearchResult(state.search_selected_index + 1))
            } else {
                None
            }
        }
        // Clear search
        (KeyModifiers::CONTROL, KeyCode::Char('l')) => Some(Action::ClearSearch),
        // Toggle regex
        (KeyModifiers::CONTROL, KeyCode::Char('r')) => {
            Some(Action::ToggleSearchFilter("regex".to_string()))
        }
        // Select for export
        (KeyModifiers::NONE, KeyCode::Char(' ')) => {
            if let Some(result) = state.search_results.get(state.search_selected_index) {
                Some(Action::ToggleConversationSelection(
                    result.conversation.id.clone(),
                ))
            } else {
                None
            }
        }
        _ => None,
    }
}
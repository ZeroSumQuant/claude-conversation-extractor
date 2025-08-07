use crate::{
    state::{Action, AppState},
    ui::{theme::Theme, widgets::FileTreeWidget},
};
use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    text::{Line, Span},
    widgets::Paragraph,
    Frame,
};

pub fn render(frame: &mut Frame, area: Rect, state: &mut AppState, theme: &Theme) {
    let chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage(40),  // File tree
            Constraint::Percentage(60),  // Preview/details
        ])
        .split(area);
    
    render_file_tree(frame, chunks[0], state, theme);
    render_preview(frame, chunks[1], state, theme);
}

fn render_file_tree(frame: &mut Frame, area: Rect, state: &mut AppState, theme: &Theme) {
    let block = theme
        .create_block("File Browser")
        .border_style(theme.primary_style());
    
    // Clone the values we need before the mutable borrow
    let selected = state.browser_selected_index;
    let scroll = state.browser_scroll_offset;
    
    // Use custom file tree widget  
    let tree_widget = FileTreeWidget::new(&state.file_tree, theme)
        .block(block)
        .selected_index(selected)
        .scroll_offset(scroll);
    
    frame.render_widget(tree_widget, area);
}

fn render_preview(frame: &mut Frame, area: Rect, state: &AppState, theme: &Theme) {
    let block = theme
        .create_block("Preview")
        .border_style(theme.secondary_style());
    
    // Get selected file info
    let selected_path = get_selected_path(state);
    
    if let Some(path) = selected_path {
        let content = if path.is_dir() {
            // Show directory contents
            vec![
                Line::from(vec![
                    Span::styled("Directory: ", theme.muted_style()),
                    Span::styled(
                        path.file_name()
                            .and_then(|n| n.to_str())
                            .unwrap_or(""),
                        theme.primary_style(),
                    ),
                ]),
                Line::from(""),
                Line::from(Span::styled("Contents:", theme.secondary_style())),
                Line::from(""),
            ]
        } else {
            // Show file preview
            vec![
                Line::from(vec![
                    Span::styled("File: ", theme.muted_style()),
                    Span::styled(
                        path.file_name()
                            .and_then(|n| n.to_str())
                            .unwrap_or(""),
                        theme.primary_style(),
                    ),
                ]),
                Line::from(""),
                Line::from(vec![
                    Span::styled("Size: ", theme.muted_style()),
                    Span::styled("calculating...", theme.secondary_style()),
                ]),
                Line::from(""),
                Line::from(Span::styled("Preview:", theme.secondary_style())),
                Line::from(""),
                Line::from(Span::styled(
                    "Press Enter to open in search",
                    theme.muted_style(),
                )),
            ]
        };
        
        let paragraph = Paragraph::new(content).block(block);
        frame.render_widget(paragraph, area);
    } else {
        let paragraph = Paragraph::new(vec![
            Line::from(""),
            Line::from(Span::styled(
                "No file selected",
                theme.muted_style(),
            )),
            Line::from(""),
            Line::from(Span::styled(
                "Use arrow keys to navigate",
                theme.muted_style(),
            )),
        ])
        .block(block);
        
        frame.render_widget(paragraph, area);
    }
}

fn get_selected_path(state: &AppState) -> Option<std::path::PathBuf> {
    // Get the currently selected path from the file tree
    // This is a simplified version - in production, you'd traverse the tree properly
    if state.browser_selected_index < state.file_tree.nodes.len() {
        Some(state.file_tree.nodes[state.browser_selected_index].path.clone())
    } else {
        None
    }
}

pub fn handle_key(key: KeyEvent, state: &AppState) -> Option<Action> {
    match (key.modifiers, key.code) {
        // Navigation
        (KeyModifiers::NONE, KeyCode::Up) | (KeyModifiers::NONE, KeyCode::Char('k')) => {
            Some(Action::BrowserSelectPrevious)
        }
        (KeyModifiers::NONE, KeyCode::Down) | (KeyModifiers::NONE, KeyCode::Char('j')) => {
            Some(Action::BrowserSelectNext)
        }
        (KeyModifiers::NONE, KeyCode::Left) | (KeyModifiers::NONE, KeyCode::Char('h')) => {
            // Collapse directory
            get_selected_path(state).map(|path| Action::ToggleDirectory(path))
        }
        (KeyModifiers::NONE, KeyCode::Right) | (KeyModifiers::NONE, KeyCode::Char('l')) => {
            // Expand directory
            get_selected_path(state).map(|path| Action::ToggleDirectory(path))
        }
        (KeyModifiers::NONE, KeyCode::Enter) => {
            // Open file/directory
            get_selected_path(state).map(|path| Action::SelectFile(path))
        }
        (KeyModifiers::NONE, KeyCode::Char(' ')) => {
            // Toggle selection for export
            get_selected_path(state).and_then(|path| {
                path.to_str()
                    .map(|s| Action::ToggleConversationSelection(s.to_string()))
            })
        }
        (KeyModifiers::NONE, KeyCode::Char('r')) => {
            // Refresh file tree
            Some(Action::RefreshFileTree)
        }
        (KeyModifiers::CONTROL, KeyCode::Char('u')) => {
            // Page up
            Some(Action::BrowserScrollUp)
        }
        (KeyModifiers::CONTROL, KeyCode::Char('d')) => {
            // Page down
            Some(Action::BrowserScrollDown)
        }
        _ => None,
    }
}
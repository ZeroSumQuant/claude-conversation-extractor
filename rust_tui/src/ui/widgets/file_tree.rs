use crate::{
    state::{FileTree, FileNode},
    ui::theme::Theme,
};
use ratatui::{
    buffer::Buffer,
    layout::Rect,
    style::Modifier,
    text::{Line, Span},
    widgets::{Block, List, ListItem, Widget},
};

fn build_tree_items_simple<'a>(
    items: &mut Vec<ListItem<'a>>,
    node: &'a FileNode,
    depth: usize,
    theme: &'a Theme,
) {
    let indent = "  ".repeat(depth);
    let icon = if node.is_dir { "📁" } else { "📄" };
    let size_str = if node.is_dir {
        String::new()
    } else {
        format!(" ({})", format_size(node.size))
    };
    
    let line = Line::from(vec![
        Span::raw(indent),
        Span::raw(icon),
        Span::raw(" "),
        Span::styled(&node.name, theme.base_style()),
        Span::styled(size_str, theme.muted_style()),
    ]);
    
    items.push(ListItem::new(line));
    
    // Add children if expanded
    if node.expanded {
        for child in &node.children {
            build_tree_items_simple(items, child, depth + 1, theme);
        }
    }
}

fn format_size(size: u64) -> String {
    if size < 1024 {
        format!("{}B", size)
    } else if size < 1024 * 1024 {
        format!("{:.1}KB", size as f64 / 1024.0)
    } else if size < 1024 * 1024 * 1024 {
        format!("{:.1}MB", size as f64 / (1024.0 * 1024.0))
    } else {
        format!("{:.1}GB", size as f64 / (1024.0 * 1024.0 * 1024.0))
    }
}

pub struct FileTreeWidget<'a> {
    tree: &'a FileTree,
    theme: &'a Theme,
    block: Option<Block<'a>>,
    selected_index: usize,
    scroll_offset: usize,
}

impl<'a> FileTreeWidget<'a> {
    pub fn new(tree: &'a FileTree, theme: &'a Theme) -> Self {
        Self {
            tree,
            theme,
            block: None,
            selected_index: 0,
            scroll_offset: 0,
        }
    }
    
    pub fn block(mut self, block: Block<'a>) -> Self {
        self.block = Some(block);
        self
    }
    
    pub fn selected_index(mut self, index: usize) -> Self {
        self.selected_index = index;
        self
    }
    
    pub fn scroll_offset(mut self, offset: usize) -> Self {
        self.scroll_offset = offset;
        self
    }
}

impl<'a> Widget for FileTreeWidget<'a> {
    fn render(self, area: Rect, buf: &mut Buffer) {
        let mut items = Vec::new();
        
        // Build the tree items recursively
        for node in &self.tree.nodes {
            build_tree_items_simple(
                &mut items,
                node,
                0,
                self.theme,
            );
        }
        
        // Apply scroll offset and limit to visible area
        let visible_items: Vec<ListItem> = items
            .into_iter()
            .skip(self.scroll_offset)
            .take(area.height as usize - 2) // Account for borders
            .collect();
        
        let list = List::new(visible_items)
            .style(self.theme.base_style())
            .highlight_style(self.theme.selection_style())
            .highlight_symbol("> ");
        
        if let Some(block) = self.block {
            Widget::render(list.block(block), area, buf);
        } else {
            Widget::render(list, area, buf);
        }
    }
}

fn build_tree_items(
    items: &mut Vec<ListItem<'static>>,
    node: &crate::state::FileNode,
    depth: usize,
    expanded_dirs: &std::collections::HashMap<std::path::PathBuf, bool>,
    theme: &Theme,
) {
    let indent = "  ".repeat(depth);
    
    let icon = if node.is_dir {
        let is_expanded = expanded_dirs.get(&node.path).copied().unwrap_or(false);
        if is_expanded {
            "▼ "
        } else {
            "▶ "
        }
    } else {
        "  "
    };
    
    let name_style = if node.is_dir {
        theme.primary_style().add_modifier(Modifier::BOLD)
    } else {
        theme.secondary_style()
    };
    
    let size_text = if node.is_dir {
        format!("[dir]")
    } else {
        format_size(node.size)
    };
    
    let line = Line::from(vec![
        Span::raw(indent),
        Span::styled(icon, theme.accent_style()),
        Span::styled(node.name.clone(), name_style),
        Span::raw(" "),
        Span::styled(size_text, theme.muted_style()),
    ]);
    
    items.push(ListItem::new(line));
    
    // Add children if directory is expanded
    if node.is_dir && expanded_dirs.get(&node.path).copied().unwrap_or(false) {
        for child in &node.children {
            build_tree_items(items, child, depth + 1, expanded_dirs, theme);
        }
    }
}


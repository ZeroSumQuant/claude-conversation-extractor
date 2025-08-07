use pyo3::prelude::*;
use pyo3::wrap_pyfunction;
use std::path::PathBuf;
use crossterm::{
    event::{DisableMouseCapture, EnableMouseCapture},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, Terminal};
use std::io;
use anyhow::Result;

// Helper functions for terminal management
pub fn setup_terminal() -> Result<Terminal<CrosstermBackend<io::Stdout>>> {
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let terminal = Terminal::new(backend)?;
    Ok(terminal)
}

pub fn restore_terminal(terminal: &mut Terminal<CrosstermBackend<io::Stdout>>) -> Result<()> {
    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    terminal.show_cursor()?;
    Ok(())
}

pub async fn run_app(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    app: &mut crate::app::App,
    mut event_handler: crate::events::EventHandler,
) -> Result<()> {
    loop {
        // Draw UI
        terminal.draw(|f| app.draw(f))?;

        // Handle events
        match event_handler.next().await? {
            crate::events::Event::Key(key) => {
                if !app.handle_key(key).await? {
                    break;
                }
            }
            crate::events::Event::Resize(width, height) => {
                app.handle_resize(width, height);
            }
            crate::events::Event::Tick => {
                app.tick().await?;
            }
        }
    }

    Ok(())
}

/// Launch the Claude TUI application
#[pyfunction]
#[pyo3(signature = (config_path=None))]
fn launch_tui(config_path: Option<String>) -> PyResult<()> {
    // Set up async runtime
    let runtime = tokio::runtime::Runtime::new()
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(format!("Failed to create runtime: {}", e)))?;
    
    runtime.block_on(async {
        // Load config
        let config = if let Some(path) = config_path {
            crate::config::Config::load().await
                .map_err(|e| PyErr::new::<pyo3::exceptions::PyIOError, _>(format!("Failed to load config: {}", e)))?
        } else {
            crate::config::Config::default()
        };
        
        // Create and run app
        let mut app = crate::app::App::new(config).await
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(format!("Failed to create app: {}", e)))?;
        
        // Setup terminal
        let mut terminal = setup_terminal()
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(format!("Failed to setup terminal: {}", e)))?;
        
        let event_handler = crate::events::EventHandler::new();
        
        // Run the app
        let result = run_app(&mut terminal, &mut app, event_handler).await;
        
        // Restore terminal
        restore_terminal(&mut terminal)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(format!("Failed to restore terminal: {}", e)))?;
        
        result.map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(format!("Application error: {}", e)))
    })
}

/// Search for conversations using the Rust search engine
#[pyfunction]
fn search_conversations(query: String, use_regex: bool) -> PyResult<Vec<SearchResult>> {
    let runtime = tokio::runtime::Runtime::new()
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(format!("Failed to create runtime: {}", e)))?;
    
    runtime.block_on(async {
        let search_engine = crate::backend::SearchEngine::new();
        
        let results = if use_regex {
            search_engine.search_regex(&query).await
        } else {
            search_engine.search(&query).await
        }
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(format!("Search failed: {}", e)))?;
        
        Ok(results.into_iter().map(|r| SearchResult {
            conversation_id: r.conversation.id,
            title: r.conversation.title,
            project: r.conversation.project,
            score: r.score,
            match_count: r.matches.len(),
        }).collect())
    })
}

/// Export conversations to various formats
#[pyfunction]
fn export_conversations(
    conversation_ids: Vec<String>,
    format: String,
    output_path: String,
) -> PyResult<()> {
    let runtime = tokio::runtime::Runtime::new()
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(format!("Failed to create runtime: {}", e)))?;
    
    runtime.block_on(async {
        let export_manager = crate::backend::ExportManager::new();
        
        let format = match format.as_str() {
            "markdown" | "md" => crate::state::ExportFormat::Markdown,
            "json" => crate::state::ExportFormat::Json,
            "html" => crate::state::ExportFormat::Html,
            "pdf" => crate::state::ExportFormat::Pdf,
            "zip" => crate::state::ExportFormat::Zip,
            _ => return Err(PyErr::new::<pyo3::exceptions::PyValueError, _>(
                format!("Unknown format: {}", format)
            )),
        };
        
        export_manager
            .export(&conversation_ids, format, PathBuf::from(output_path))
            .await
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyIOError, _>(format!("Export failed: {}", e)))
    })
}

/// Get conversation statistics
#[pyfunction]
fn get_stats() -> PyResult<ConversationStats> {
    let runtime = tokio::runtime::Runtime::new()
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(format!("Failed to create runtime: {}", e)))?;
    
    runtime.block_on(async {
        let manager = crate::backend::ConversationManager::new().await
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(format!("Failed to create manager: {}", e)))?;
        
        let count = manager.count_conversations().await
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyIOError, _>(format!("Failed to count conversations: {}", e)))?;
        
        let size = manager.calculate_total_size().await
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyIOError, _>(format!("Failed to calculate size: {}", e)))?;
        
        Ok(ConversationStats {
            total_conversations: count,
            total_size_bytes: size,
            size_mb: (size as f64) / 1_048_576.0,
        })
    })
}

#[pyclass]
#[derive(Clone)]
struct SearchResult {
    #[pyo3(get)]
    conversation_id: String,
    #[pyo3(get)]
    title: String,
    #[pyo3(get)]
    project: String,
    #[pyo3(get)]
    score: f32,
    #[pyo3(get)]
    match_count: usize,
}

#[pyclass]
#[derive(Clone)]
struct ConversationStats {
    #[pyo3(get)]
    total_conversations: usize,
    #[pyo3(get)]
    total_size_bytes: u64,
    #[pyo3(get)]
    size_mb: f64,
}

/// Python module for Claude TUI
#[pymodule]
fn _claude_tui(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(launch_tui, m)?)?;
    m.add_function(wrap_pyfunction!(search_conversations, m)?)?;
    m.add_function(wrap_pyfunction!(export_conversations, m)?)?;
    m.add_function(wrap_pyfunction!(get_stats, m)?)?;
    m.add_class::<SearchResult>()?;
    m.add_class::<ConversationStats>()?;
    Ok(())
}
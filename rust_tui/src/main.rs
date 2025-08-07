use anyhow::Result;
use claude_tui::{app::App, config::Config, events::EventHandler};
use crossterm::{
    event::{DisableMouseCapture, EnableMouseCapture},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, Terminal};
use std::io;
use tracing_subscriber::{fmt, prelude::*, EnvFilter};

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    let log_file = dirs::data_dir()
        .unwrap_or_else(|| std::path::PathBuf::from("."))
        .join("claude-tui")
        .join("claude-tui.log");
    
    std::fs::create_dir_all(log_file.parent().unwrap())?;
    
    let file_appender = tracing_subscriber::fmt::layer()
        .with_file(true)
        .with_line_number(true)
        .with_writer(std::fs::File::create(&log_file)?);
    
    tracing_subscriber::registry()
        .with(file_appender)
        .with(EnvFilter::from_default_env().add_directive(tracing::Level::INFO.into()))
        .init();

    tracing::info!("Starting Claude TUI");

    // Load configuration
    let config = Config::load().await?;

    // Setup terminal
    let mut terminal = setup_terminal()?;

    // Create app and event handler
    let mut app = App::new(config).await?;
    let event_handler = EventHandler::new();

    // Run the app
    let result = run_app(&mut terminal, &mut app, event_handler).await;

    // Restore terminal
    restore_terminal(&mut terminal)?;

    if let Err(e) = result {
        tracing::error!("Application error: {}", e);
        eprintln!("Error: {}", e);
        std::process::exit(1);
    }

    tracing::info!("Claude TUI shutdown gracefully");
    Ok(())
}

pub async fn run_app(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    app: &mut App,
    mut event_handler: EventHandler,
) -> Result<()> {
    loop {
        // Draw UI
        terminal.draw(|f| app.draw(f))?;

        // Handle events
        match event_handler.next().await? {
            claude_tui::events::Event::Key(key) => {
                if !app.handle_key(key).await? {
                    break;
                }
            }
            claude_tui::events::Event::Resize(width, height) => {
                app.handle_resize(width, height);
            }
            claude_tui::events::Event::Tick => {
                app.tick().await?;
            }
        }
    }

    Ok(())
}

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
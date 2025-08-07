pub mod app;
pub mod backend;
pub mod config;
pub mod events;
#[cfg(feature = "python")]
pub mod python_bindings;
pub mod state;
pub mod ui;

// Re-export commonly used types
pub use app::App;
pub use config::Config;
pub use events::{Event, EventHandler};
pub use state::{Action, AppState};

// Version information
pub const VERSION: &str = env!("CARGO_PKG_VERSION");
pub const NAME: &str = env!("CARGO_PKG_NAME");
use chrono::{DateTime, Local};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, VecDeque};
use std::path::PathBuf;

#[derive(Debug, Clone, PartialEq)]
pub enum Page {
    Home,
    Browser,
    Search,
    Export,
    Statistics,
    Settings,
}

#[derive(Debug, Clone)]
pub struct AppState {
    pub current_page: Page,
    pub previous_page: Option<Page>,
    
    // Global state
    pub total_conversations: usize,
    pub total_size: u64,
    pub last_sync: Option<DateTime<Local>>,
    pub terminal_size: (u16, u16),
    
    // Conversations
    pub conversations: Vec<Conversation>,
    pub recent_conversations: Vec<Conversation>,
    pub selected_conversations: Vec<String>,
    pub home_selected_index: usize,
    
    // File browser state
    pub file_tree: FileTree,
    pub expanded_dirs: HashMap<PathBuf, bool>,
    pub browser_scroll_offset: usize,
    pub browser_selected_index: usize,
    
    // Search state
    pub search_query: String,
    pub search_results: Vec<SearchResult>,
    pub search_history: VecDeque<String>,
    pub search_filters: SearchFilters,
    pub search_selected_index: usize,
    pub search_scroll_offset: usize,
    
    // Export state
    pub export_queue: Vec<ExportJob>,
    pub export_format: ExportFormat,
    pub export_path: PathBuf,
    pub export_progress: Option<ExportProgress>,
    
    // Statistics
    pub stats: Statistics,
    
    // Settings
    pub settings: Settings,
    
    // UI state
    pub notifications: VecDeque<Notification>,
    pub active_modal: Option<Modal>,
    pub command_palette_open: bool,
    pub command_palette_query: String,
    pub tick_count: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Conversation {
    pub id: String,
    pub title: String,
    pub project: String,
    pub created_at: DateTime<Local>,
    pub updated_at: DateTime<Local>,
    pub message_count: usize,
    pub size_bytes: u64,
    pub path: PathBuf,
    pub tags: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct FileTree {
    pub root: PathBuf,
    pub nodes: Vec<FileNode>,
    pub loaded: bool,
}

#[derive(Debug, Clone)]
pub struct FileNode {
    pub path: PathBuf,
    pub name: String,
    pub is_dir: bool,
    pub size: u64,
    pub modified: DateTime<Local>,
    pub children: Vec<FileNode>,
    pub expanded: bool,
    pub depth: usize,
}

#[derive(Debug, Clone)]
pub struct SearchResult {
    pub conversation: Conversation,
    pub score: f32,
    pub matches: Vec<Match>,
}

#[derive(Debug, Clone)]
pub struct Match {
    pub field: String,
    pub text: String,
    pub positions: Vec<(usize, usize)>,
}

#[derive(Debug, Clone, Default)]
pub struct SearchFilters {
    pub date_from: Option<DateTime<Local>>,
    pub date_to: Option<DateTime<Local>>,
    pub projects: Vec<String>,
    pub min_messages: Option<usize>,
    pub max_messages: Option<usize>,
    pub tags: Vec<String>,
    pub use_regex: bool,
}

#[derive(Debug, Clone)]
pub struct ExportJob {
    pub id: String,
    pub conversations: Vec<String>,
    pub format: ExportFormat,
    pub path: PathBuf,
    pub status: ExportStatus,
    pub created_at: DateTime<Local>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ExportFormat {
    Markdown,
    Json,
    Html,
    Pdf,
    Zip,
}

#[derive(Debug, Clone)]
pub enum ExportStatus {
    Pending,
    InProgress(f32),
    Completed,
    Failed(String),
}

#[derive(Debug, Clone)]
pub struct ExportProgress {
    pub current: usize,
    pub total: usize,
    pub message: String,
}

#[derive(Debug, Clone, Default)]
pub struct Statistics {
    pub conversations_by_day: Vec<(DateTime<Local>, usize)>,
    pub conversations_by_project: HashMap<String, usize>,
    pub message_count_distribution: Vec<(String, usize)>,
    pub storage_by_project: HashMap<String, u64>,
    pub activity_heatmap: Vec<Vec<f32>>,
    pub top_tags: Vec<(String, usize)>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Settings {
    pub theme: String,
    pub auto_sync: bool,
    pub sync_interval_minutes: u32,
    pub default_export_format: String,
    pub default_export_path: PathBuf,
    pub search_history_size: usize,
    pub show_hidden_files: bool,
    pub vim_mode: bool,
    pub confirm_on_delete: bool,
    pub notification_timeout_seconds: u32,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            theme: "claude".to_string(),
            auto_sync: true,
            sync_interval_minutes: 60,
            default_export_format: "markdown".to_string(),
            default_export_path: dirs::home_dir().unwrap_or_default(),
            search_history_size: 50,
            show_hidden_files: false,
            vim_mode: true,
            confirm_on_delete: true,
            notification_timeout_seconds: 5,
        }
    }
}

#[derive(Debug, Clone)]
pub struct Notification {
    pub id: String,
    pub message: String,
    pub level: NotificationLevel,
    pub created_at: DateTime<Local>,
    pub expires_at: DateTime<Local>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum NotificationLevel {
    Info,
    Success,
    Warning,
    Error,
}

#[derive(Debug, Clone)]
pub enum Modal {
    Confirm {
        title: String,
        message: String,
        on_confirm: Box<Action>,
        on_cancel: Option<Box<Action>>,
    },
    Input {
        title: String,
        prompt: String,
        value: String,
        on_submit: Box<Action>,
        on_cancel: Option<Box<Action>>,
    },
    Help,
    CommandPalette {
        query: String,
        commands: Vec<Command>,
        selected_index: usize,
    },
}

#[derive(Debug, Clone)]
pub struct Command {
    pub name: String,
    pub description: String,
    pub shortcut: Option<String>,
    pub action: Action,
}

#[derive(Debug, Clone)]
pub enum Action {
    // Navigation
    NavigateToPage(Page),
    NavigateBack,
    
    // File browser
    ToggleDirectory(PathBuf),
    SelectFile(PathBuf),
    RefreshFileTree,
    BrowserScrollUp,
    BrowserScrollDown,
    BrowserSelectPrevious,
    BrowserSelectNext,
    
    // Search
    UpdateSearchQuery(String),
    ExecuteSearch,
    ClearSearch,
    ToggleSearchFilter(String),
    SelectSearchResult(usize),
    SearchScrollUp,
    SearchScrollDown,
    
    // Export
    AddToExportQueue(Vec<String>),
    SetExportFormat(ExportFormat),
    SetExportPath(PathBuf),
    StartExport,
    CancelExport(String),
    ClearExportQueue,
    
    // Conversations
    SetConversations(Vec<Conversation>),
    SelectConversation(String),
    DeselectConversation(String),
    ToggleConversationSelection(String),
    OpenConversation(PathBuf),
    DeleteConversation(String),
    HomeSelectNext,
    HomeSelectPrevious,
    
    // Search results
    SetSearchResults(Vec<SearchResult>),
    
    // Statistics
    UpdateStats(Statistics),
    RefreshStatistics,
    
    // Settings
    UpdateSetting(String, String),
    SaveSettings,
    ResetSettings,
    
    // Modals
    ShowModal(Modal),
    CloseModal,
    ShowCommandPalette,
    ShowHelp,
    ShowConfirm(String, String, Box<Action>),
    ShowInput(String, String, Box<Action>),
    
    // Notifications
    ShowNotification(String, NotificationLevel),
    DismissNotification(String),
    ClearNotifications,
    
    // Export
    ExportComplete,
    
    // Misc
    CancelCurrentOperation,
    Tick,
}

#[derive(Debug, Clone)]
pub enum Effect {
    LoadConversations,
    SearchConversations(String),
    ExportConversations(Vec<String>, ExportFormat, PathBuf),
    RefreshStats,
    SaveConfig,
    ShowNotification(String, NotificationLevel),
    OpenFile(PathBuf),
}

impl AppState {
    pub fn new() -> Self {
        Self {
            current_page: Page::Home,
            previous_page: None,
            total_conversations: 0,
            total_size: 0,
            last_sync: None,
            terminal_size: (80, 24),
            conversations: Vec::new(),
            recent_conversations: Vec::new(),
            selected_conversations: Vec::new(),
            home_selected_index: 0,
            file_tree: FileTree {
                root: dirs::home_dir()
                    .unwrap_or_default()
                    .join(".claude")
                    .join("projects"),
                nodes: Vec::new(),
                loaded: false,
            },
            expanded_dirs: HashMap::new(),
            browser_scroll_offset: 0,
            browser_selected_index: 0,
            search_query: String::new(),
            search_results: Vec::new(),
            search_history: VecDeque::with_capacity(50),
            search_filters: SearchFilters::default(),
            search_selected_index: 0,
            search_scroll_offset: 0,
            export_queue: Vec::new(),
            export_format: ExportFormat::Markdown,
            export_path: dirs::home_dir().unwrap_or_default(),
            export_progress: None,
            stats: Statistics::default(),
            settings: Settings::default(),
            notifications: VecDeque::new(),
            active_modal: None,
            command_palette_open: false,
            command_palette_query: String::new(),
            tick_count: 0,
        }
    }
    
    pub fn reduce(&mut self, action: Action) -> Vec<Effect> {
        let mut effects = Vec::new();
        
        match action {
            Action::NavigateToPage(page) => {
                if self.current_page != page {
                    self.previous_page = Some(self.current_page.clone());
                    self.current_page = page;
                    
                    // Load data for the new page if needed
                    match self.current_page {
                        Page::Browser if !self.file_tree.loaded => {
                            effects.push(Effect::LoadConversations);
                        }
                        Page::Statistics if self.stats.conversations_by_day.is_empty() => {
                            effects.push(Effect::RefreshStats);
                        }
                        _ => {}
                    }
                }
            }
            
            Action::NavigateBack => {
                if let Some(prev) = self.previous_page.take() {
                    let current = self.current_page.clone();
                    self.current_page = prev;
                    self.previous_page = Some(current);
                }
            }
            
            Action::UpdateSearchQuery(query) => {
                self.search_query = query;
            }
            
            Action::ExecuteSearch => {
                if !self.search_query.is_empty() {
                    self.search_history.push_front(self.search_query.clone());
                    if self.search_history.len() > self.settings.search_history_size {
                        self.search_history.pop_back();
                    }
                    effects.push(Effect::SearchConversations(self.search_query.clone()));
                }
            }
            
            Action::SetSearchResults(results) => {
                self.search_results = results;
                self.search_selected_index = 0;
                self.search_scroll_offset = 0;
            }
            
            Action::ShowNotification(message, level) => {
                self.add_notification(message, level);
            }
            
            Action::ShowModal(modal) => {
                self.active_modal = Some(modal);
            }
            
            Action::CloseModal => {
                self.active_modal = None;
            }
            
            Action::Tick => {
                self.tick_count += 1;
            }
            
            Action::HomeSelectNext => {
                if self.home_selected_index < self.recent_conversations.len().saturating_sub(1) {
                    self.home_selected_index += 1;
                }
            }
            
            Action::HomeSelectPrevious => {
                if self.home_selected_index > 0 {
                    self.home_selected_index -= 1;
                }
            }
            
            Action::OpenConversation(path) => {
                effects.push(Effect::OpenFile(path));
            }
            
            Action::BrowserSelectNext => {
                if self.browser_selected_index < self.file_tree.nodes.len().saturating_sub(1) {
                    self.browser_selected_index += 1;
                }
            }
            
            Action::BrowserSelectPrevious => {
                if self.browser_selected_index > 0 {
                    self.browser_selected_index -= 1;
                }
            }
            
            _ => {
                // Handle other actions...
            }
        }
        
        effects
    }
    
    pub fn add_notification(&mut self, message: String, level: NotificationLevel) {
        let now = Local::now();
        let expires_at = now + chrono::Duration::seconds(self.settings.notification_timeout_seconds as i64);
        
        let notification = Notification {
            id: format!("{}", now.timestamp_nanos_opt().unwrap_or(0)),
            message,
            level,
            created_at: now,
            expires_at,
        };
        
        self.notifications.push_back(notification);
        
        // Keep only last 10 notifications
        while self.notifications.len() > 10 {
            self.notifications.pop_front();
        }
    }
    
    pub fn update_tick(&mut self) {
        // Remove expired notifications
        let now = Local::now();
        self.notifications.retain(|n| n.expires_at > now);
    }
}
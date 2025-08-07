use crate::{
    backend::{ConversationManager, ExportManager, SearchEngine},
    config::Config,
    state::{Action, AppState, Effect, Page},
    ui::{pages, theme::Theme, widgets::NotificationWidget},
};
use anyhow::Result;
use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use ratatui::{layout::Rect, Frame};
use std::sync::Arc;
use tokio::sync::mpsc;

pub struct App {
    pub state: AppState,
    pub config: Config,
    pub theme: Theme,
    
    // Backend services
    conversation_manager: Arc<ConversationManager>,
    search_engine: Arc<SearchEngine>,
    export_manager: Arc<ExportManager>,
    
    // Channels for async operations
    action_tx: mpsc::UnboundedSender<Action>,
    action_rx: mpsc::UnboundedReceiver<Action>,
    effect_tx: mpsc::UnboundedSender<Effect>,
    effect_rx: mpsc::UnboundedReceiver<Effect>,
}

impl App {
    pub async fn new(config: Config) -> Result<Self> {
        let theme = Theme::from_name(&config.theme)?;
        
        // Initialize backend services
        let conversation_manager = Arc::new(ConversationManager::new().await?);
        let search_engine = Arc::new(SearchEngine::new());
        let export_manager = Arc::new(ExportManager::new());
        
        // Create channels
        let (action_tx, action_rx) = mpsc::unbounded_channel();
        let (effect_tx, effect_rx) = mpsc::unbounded_channel();
        
        // Initialize state
        let mut state = AppState::new();
        
        // Load initial data
        state.total_conversations = conversation_manager.count_conversations().await?;
        state.total_size = conversation_manager.calculate_total_size().await?;
        state.recent_conversations = conversation_manager.get_recent(10).await?;
        
        Ok(Self {
            state,
            config,
            theme,
            conversation_manager,
            search_engine,
            export_manager,
            action_tx,
            action_rx,
            effect_tx,
            effect_rx,
        })
    }
    
    pub fn draw(&mut self, frame: &mut Frame) {
        let area = frame.area();
        
        // Draw background
        self.theme.draw_background(frame, area);
        
        // Draw header
        let header_area = Rect::new(area.x, area.y, area.width, 3);
        self.draw_header(frame, header_area);
        
        // Draw main content
        let content_area = Rect::new(
            area.x,
            area.y + 3,
            area.width,
            area.height.saturating_sub(6),
        );
        self.draw_current_page(frame, content_area);
        
        // Draw status bar
        let status_area = Rect::new(
            area.x,
            area.y + area.height - 3,
            area.width,
            3,
        );
        self.draw_status_bar(frame, status_area);
        
        // Draw notifications (overlay)
        if !self.state.notifications.is_empty() {
            frame.render_widget(
                NotificationWidget::new(&self.state.notifications, &self.theme),
                area
            );
        }
        
        // Draw modal if active
        if let Some(modal) = &self.state.active_modal {
            self.draw_modal(frame, area, modal);
        }
    }
    
    fn draw_header(&self, frame: &mut Frame, area: Rect) {
        pages::header::render(frame, area, &self.state, &self.theme);
    }
    
    fn draw_current_page(&mut self, frame: &mut Frame, area: Rect) {
        match self.state.current_page {
            Page::Home => pages::home::render(frame, area, &self.state, &self.theme),
            Page::Browser => pages::browser::render(frame, area, &mut self.state, &self.theme),
            Page::Search => pages::search::render(frame, area, &mut self.state, &self.theme),
            Page::Export => pages::export::render(frame, area, &mut self.state, &self.theme),
            Page::Statistics => pages::stats::render(frame, area, &self.state, &self.theme),
            Page::Settings => pages::settings::render(frame, area, &mut self.state, &self.theme),
        }
    }
    
    fn draw_status_bar(&self, frame: &mut Frame, area: Rect) {
        pages::status_bar::render(frame, area, &self.state, &self.theme);
    }
    
    fn draw_modal(&self, frame: &mut Frame, area: Rect, modal: &crate::state::Modal) {
        pages::modal::render(frame, area, modal, &self.theme);
    }
    
    pub async fn handle_key(&mut self, key: KeyEvent) -> Result<bool> {
        tracing::debug!("Key pressed: {:?}", key);
        
        // Global keybindings
        match (key.modifiers, key.code) {
            // Quit (q without modifier or Ctrl+C)
            (KeyModifiers::NONE, KeyCode::Char('q')) => return Ok(false),
            (KeyModifiers::CONTROL, KeyCode::Char('c')) => return Ok(false),
            
            // Theme switching
            (KeyModifiers::NONE, KeyCode::Char('t')) => {
                self.cycle_theme()?;
            }
            
            // Command palette
            (KeyModifiers::NONE, KeyCode::Char('/')) if self.state.active_modal.is_none() => {
                self.dispatch(Action::ShowCommandPalette);
            }
            
            // Page navigation (1-6)
            (KeyModifiers::NONE, KeyCode::Char(c)) if c >= '1' && c <= '6' && self.state.active_modal.is_none() => {
                let page = match c {
                    '1' => Page::Home,
                    '2' => Page::Browser,
                    '3' => Page::Search,
                    '4' => Page::Export,
                    '5' => Page::Statistics,
                    '6' => Page::Settings,
                    _ => unreachable!(),
                };
                self.dispatch(Action::NavigateToPage(page));
            }
            
            // Help
            (KeyModifiers::NONE, KeyCode::Char('?')) => {
                self.dispatch(Action::ShowHelp);
            }
            
            // Escape - close modals or cancel operations
            (KeyModifiers::NONE, KeyCode::Esc) => {
                if self.state.active_modal.is_some() {
                    self.dispatch(Action::CloseModal);
                } else {
                    self.dispatch(Action::CancelCurrentOperation);
                }
            }
            
            // Page-specific keybindings
            _ => {
                self.handle_page_key(key).await?;
            }
        }
        
        Ok(true)
    }
    
    async fn handle_page_key(&mut self, key: KeyEvent) -> Result<()> {
        let action = match self.state.current_page {
            Page::Home => pages::home::handle_key(key, &self.state),
            Page::Browser => pages::browser::handle_key(key, &self.state),
            Page::Search => pages::search::handle_key(key, &self.state),
            Page::Export => pages::export::handle_key(key, &self.state),
            Page::Statistics => pages::stats::handle_key(key, &self.state),
            Page::Settings => pages::settings::handle_key(key, &self.state),
        };
        
        if let Some(action) = action {
            self.dispatch(action);
        }
        
        Ok(())
    }
    
    pub fn handle_resize(&mut self, width: u16, height: u16) {
        self.state.terminal_size = (width, height);
    }
    
    pub async fn tick(&mut self) -> Result<()> {
        // Process pending actions
        while let Ok(action) = self.action_rx.try_recv() {
            self.process_action(action).await?;
        }
        
        // Process effects
        while let Ok(effect) = self.effect_rx.try_recv() {
            self.process_effect(effect).await?;
        }
        
        // Update time-based state
        self.state.update_tick();
        
        Ok(())
    }
    
    fn dispatch(&self, action: Action) {
        let _ = self.action_tx.send(action);
    }
    
    async fn process_action(&mut self, action: Action) -> Result<()> {
        let effects = self.state.reduce(action);
        
        for effect in effects {
            let _ = self.effect_tx.send(effect);
        }
        
        Ok(())
    }
    
    async fn process_effect(&mut self, effect: Effect) -> Result<()> {
        match effect {
            Effect::LoadConversations => {
                let conversations = self.conversation_manager.load_all().await?;
                self.dispatch(Action::SetConversations(conversations));
            }
            Effect::SearchConversations(query) => {
                let results = self.search_engine.search(&query).await?;
                self.dispatch(Action::SetSearchResults(results));
            }
            Effect::ExportConversations(ids, format, path) => {
                self.export_manager.export(&ids, format, path).await?;
                self.dispatch(Action::ExportComplete);
            }
            Effect::RefreshStats => {
                let stats = self.conversation_manager.calculate_stats().await?;
                self.dispatch(Action::UpdateStats(stats));
            }
            Effect::SaveConfig => {
                self.config.save().await?;
            }
            Effect::ShowNotification(message, level) => {
                self.state.add_notification(message, level);
            }
            Effect::OpenFile(path) => {
                // Open the conversation file in the search view
                if let Ok(conversation) = self.conversation_manager.load_conversation(&path).await {
                    self.dispatch(Action::NavigateToPage(Page::Search));
                    // TODO: Load the conversation content into search view
                }
            }
        }
        
        Ok(())
    }
    
    fn cycle_theme(&mut self) -> Result<()> {
        let themes = ["matrix", "claude", "cyberpunk"];
        let current_index = themes.iter().position(|&t| t == self.config.theme).unwrap_or(0);
        let next_index = (current_index + 1) % themes.len();
        
        self.config.theme = themes[next_index].to_string();
        self.theme = Theme::from_name(&self.config.theme)?;
        
        self.dispatch(Action::ShowNotification(
            format!("Switched to {} theme", self.config.theme),
            crate::state::NotificationLevel::Info,
        ));
        
        Ok(())
    }
}
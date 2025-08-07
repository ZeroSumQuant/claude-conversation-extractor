use anyhow::Result;
use crossterm::event::{self, KeyEvent};
use std::time::Duration;
use tokio::sync::mpsc;
use tokio::time::interval;

#[derive(Debug, Clone)]
pub enum Event {
    Key(KeyEvent),
    Resize(u16, u16),
    Tick,
}

pub struct EventHandler {
    rx: mpsc::UnboundedReceiver<Event>,
    _tx: mpsc::UnboundedSender<Event>,
}

impl EventHandler {
    pub fn new() -> Self {
        let (tx, rx) = mpsc::unbounded_channel();
        let event_tx = tx.clone();
        let tick_tx = tx.clone();
        
        // Spawn key event handler
        tokio::spawn(async move {
            loop {
                if event::poll(Duration::from_millis(50)).unwrap_or(false) {
                    if let Ok(event) = event::read() {
                        match event {
                            event::Event::Key(key) => {
                                let _ = event_tx.send(Event::Key(key));
                            }
                            event::Event::Resize(width, height) => {
                                let _ = event_tx.send(Event::Resize(width, height));
                            }
                            _ => {}
                        }
                    }
                }
            }
        });
        
        // Spawn tick handler
        tokio::spawn(async move {
            let mut ticker = interval(Duration::from_millis(250));
            loop {
                ticker.tick().await;
                let _ = tick_tx.send(Event::Tick);
            }
        });
        
        Self { rx, _tx: tx }
    }
    
    pub async fn next(&mut self) -> Result<Event> {
        self.rx
            .recv()
            .await
            .ok_or_else(|| anyhow::anyhow!("Event channel closed"))
    }
}
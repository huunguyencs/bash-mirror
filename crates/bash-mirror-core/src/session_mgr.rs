use crate::pty_session::PtySession;
use anyhow::{anyhow, Result};
use bash_mirror_proto::SessionInfo;
use std::collections::HashMap;
use tokio::sync::mpsc;
use uuid::Uuid;

pub struct SessionManager {
    sessions: HashMap<String, PtySession>,
    output_rxs: HashMap<String, mpsc::UnboundedReceiver<Vec<u8>>>,
    shell: String,
    max_sessions: usize,
}

impl SessionManager {
    pub fn new(shell: String, max_sessions: usize) -> Self {
        Self {
            sessions: HashMap::new(),
            output_rxs: HashMap::new(),
            shell,
            max_sessions,
        }
    }

    pub fn create_session(&mut self) -> Result<(String, String)> {
        if self.sessions.len() >= self.max_sessions {
            return Err(anyhow!(
                "max sessions reached ({})",
                self.max_sessions
            ));
        }
        let id = Uuid::new_v4().to_string();
        let (session, output_rx) = PtySession::spawn(id.clone(), &self.shell, 80, 24)?;
        self.sessions.insert(id.clone(), session);
        self.output_rxs.insert(id.clone(), output_rx);
        Ok((id, self.shell.clone()))
    }

    pub fn close_session(&mut self, id: &str) -> Result<()> {
        let mut session = self
            .sessions
            .remove(id)
            .ok_or_else(|| anyhow!("session not found: {id}"))?;
        self.output_rxs.remove(id);
        session.kill();
        Ok(())
    }

    pub fn write_to_session(&self, id: &str, data: &[u8]) -> Result<()> {
        let session = self
            .sessions
            .get(id)
            .ok_or_else(|| anyhow!("session not found: {id}"))?;
        session.write_input(data)
    }

    pub fn resize_session(&self, id: &str, cols: u16, rows: u16) -> Result<()> {
        let session = self
            .sessions
            .get(id)
            .ok_or_else(|| anyhow!("session not found: {id}"))?;
        session.resize(cols, rows)
    }

    pub fn list_sessions(&mut self) -> Vec<SessionInfo> {
        self.sessions
            .iter_mut()
            .map(|(id, session)| SessionInfo {
                id: id.clone(),
                shell: self.shell.clone(),
                alive: session.is_alive(),
            })
            .collect()
    }

    pub fn take_output_rx(&mut self, id: &str) -> Option<mpsc::UnboundedReceiver<Vec<u8>>> {
        self.output_rxs.remove(id)
    }

    pub fn has_session(&self, id: &str) -> bool {
        self.sessions.contains_key(id)
    }

    pub fn session_ids(&self) -> Vec<String> {
        self.sessions.keys().cloned().collect()
    }

    pub fn check_exited(&mut self) -> Vec<(String, i32)> {
        let mut exited = Vec::new();
        for (id, session) in self.sessions.iter_mut() {
            if let Some(code) = session.try_exit_code() {
                exited.push((id.clone(), code as i32));
            }
        }
        for (id, _) in &exited {
            self.sessions.remove(id);
            self.output_rxs.remove(id);
        }
        exited
    }
}

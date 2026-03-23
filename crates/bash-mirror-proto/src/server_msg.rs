use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionInfo {
    pub id: String,
    pub shell: String,
    pub alive: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ServerMessage {
    AuthOk {
        device_id: String,
    },
    AuthFail {
        reason: String,
    },
    Output {
        session: String,
        data: String,
    },
    SessionCreated {
        session: String,
        shell: String,
    },
    SessionClosed {
        session: String,
    },
    SessionList {
        sessions: Vec<SessionInfo>,
    },
    SessionExited {
        session: String,
        code: i32,
    },
    Pong {
        timestamp: u64,
    },
    Error {
        code: String,
        message: String,
    },
}

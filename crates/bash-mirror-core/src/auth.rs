use rand::Rng;
use sha2::{Digest, Sha256};
use std::net::IpAddr;
use std::time::{Duration, Instant};
use subtle::ConstantTimeEq;
use tracing::debug;
use zeroize::Zeroizing;

pub struct PairingManager {
    active_token: Option<PairingToken>,
    token_ttl: Duration,
}

pub struct PairingToken {
    pub token: Zeroizing<String>,
    pub short_code: String,
    pub created_at: Instant,
    pub ttl: Duration,
}

impl PairingToken {
    pub fn is_expired(&self) -> bool {
        self.created_at.elapsed() > self.ttl
    }

    pub fn remaining_secs(&self) -> u64 {
        self.ttl
            .checked_sub(self.created_at.elapsed())
            .map(|d| d.as_secs())
            .unwrap_or(0)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum AuthResult {
    Valid,
    Expired,
    Invalid,
    NoToken,
}

impl PairingManager {
    pub fn new(token_ttl: Duration) -> Self {
        Self {
            active_token: None,
            token_ttl,
        }
    }

    pub fn generate_token(&mut self) -> &PairingToken {
        let mut rng = rand::thread_rng();
        let token: String = (0..32).map(|_| format!("{:x}", rng.gen::<u8>())).collect();

        // Derive 6-digit code from token hash
        let hash = Sha256::digest(token.as_bytes());
        let code_num = u32::from_be_bytes([hash[0], hash[1], hash[2], hash[3]]) % 1_000_000;
        let short_code = format!("{:06}", code_num);

        self.active_token = Some(PairingToken {
            token: Zeroizing::new(token),
            short_code,
            created_at: Instant::now(),
            ttl: self.token_ttl,
        });

        self.active_token.as_ref().unwrap()
    }

    pub fn validate_token(&mut self, token: &str) -> AuthResult {
        match &self.active_token {
            None => {
                debug!("validate_token: no active token");
                AuthResult::NoToken
            }
            Some(active) if active.is_expired() => {
                debug!(
                    "validate_token: token expired ({}s ago)",
                    active.created_at.elapsed().as_secs().saturating_sub(active.ttl.as_secs())
                );
                self.active_token = None;
                AuthResult::Expired
            }
            Some(active) => {
                let active_bytes = active.token.as_bytes();
                let input_bytes = token.as_bytes();
                debug!(
                    "validate_token: stored len={} first8={:?}, input len={} first8={:?}",
                    active_bytes.len(),
                    String::from_utf8_lossy(&active_bytes[..active_bytes.len().min(8)]),
                    input_bytes.len(),
                    String::from_utf8_lossy(&input_bytes[..input_bytes.len().min(8)]),
                );
                if active_bytes.len() == input_bytes.len()
                    && active_bytes.ct_eq(input_bytes).into()
                {
                    self.active_token = None;
                    AuthResult::Valid
                } else {
                    debug!("validate_token: mismatch (len match={})", active_bytes.len() == input_bytes.len());
                    AuthResult::Invalid
                }
            }
        }
    }

    pub fn current_token(&self) -> Option<&PairingToken> {
        self.active_token
            .as_ref()
            .filter(|t| !t.is_expired())
    }

    pub fn qr_payload(ip: IpAddr, port: u16, token: &str, cert_fingerprint: &str) -> String {
        format!(
            "bashmirror://{}:{}?token={}&fp={}",
            ip, port, token, cert_fingerprint
        )
    }
}

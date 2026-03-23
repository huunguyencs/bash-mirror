use anyhow::Result;
use rcgen::generate_simple_self_signed;
use rustls::ServerConfig;
use rustls_pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer};
use sha2::{Digest, Sha256};
use std::sync::Arc;
use tokio_rustls::TlsAcceptor;

pub struct TlsInfo {
    pub acceptor: TlsAcceptor,
    pub fingerprint: String,
    pub cert_der: Vec<u8>,
}

pub fn generate_tls(lan_ip: &str) -> Result<TlsInfo> {
    let cert_key = generate_simple_self_signed(vec![
        "localhost".to_string(),
        "bash-mirror.local".to_string(),
        lan_ip.to_string(),
    ])?;

    let cert_der = cert_key.cert.der().to_vec();
    let key_der = cert_key.key_pair.serialize_der();

    // Compute SHA-256 fingerprint
    let hash = Sha256::digest(&cert_der);
    let fingerprint = hash
        .iter()
        .map(|b| format!("{:02x}", b))
        .collect::<Vec<_>>()
        .join(":");

    let cert = CertificateDer::from(cert_der.clone());
    let key = PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(key_der));

    let config = ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(vec![cert], key)?;

    let acceptor = TlsAcceptor::from(Arc::new(config));

    Ok(TlsInfo {
        acceptor,
        fingerprint,
        cert_der,
    })
}

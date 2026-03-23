use anyhow::Result;
use portable_pty::{native_pty_system, CommandBuilder, MasterPty, PtySize};
use std::io::{Read, Write};
use tokio::sync::mpsc;
use tracing::{debug, warn};

pub struct PtySession {
    pub id: String,
    writer_tx: mpsc::UnboundedSender<Vec<u8>>,
    master: Box<dyn MasterPty + Send>,
    child: Box<dyn portable_pty::Child + Send + Sync>,
}

impl PtySession {
    pub fn spawn(
        id: String,
        shell: &str,
        cols: u16,
        rows: u16,
    ) -> Result<(Self, mpsc::UnboundedReceiver<Vec<u8>>)> {
        let pty_system = native_pty_system();
        let pair = pty_system.openpty(PtySize {
            rows,
            cols,
            pixel_width: 0,
            pixel_height: 0,
        })?;

        let mut cmd = CommandBuilder::new(shell);
        cmd.env("TERM", "xterm-256color");
        let child = pair.slave.spawn_command(cmd)?;
        drop(pair.slave);

        let mut reader = pair.master.try_clone_reader()?;
        let writer = pair.master.take_writer()?;

        // PTY output channel (reader thread -> async world)
        let (output_tx, output_rx) = mpsc::unbounded_channel();

        // Spawn dedicated reader thread
        let reader_id = id.clone();
        std::thread::spawn(move || {
            let mut buf = [0u8; 4096];
            loop {
                match reader.read(&mut buf) {
                    Ok(0) => {
                        debug!(session = %reader_id, "PTY reader EOF");
                        break;
                    }
                    Ok(n) => {
                        if output_tx.send(buf[..n].to_vec()).is_err() {
                            break;
                        }
                    }
                    Err(e) => {
                        // On macOS, EIO means slave closed
                        if e.raw_os_error() == Some(libc::EIO) {
                            debug!(session = %reader_id, "PTY reader EIO (slave closed)");
                        } else if e.kind() != std::io::ErrorKind::Interrupted {
                            warn!(session = %reader_id, error = %e, "PTY reader error");
                        }
                        if e.kind() != std::io::ErrorKind::Interrupted {
                            break;
                        }
                    }
                }
            }
        });

        // Spawn dedicated writer thread
        let (writer_tx, mut writer_rx) = mpsc::unbounded_channel::<Vec<u8>>();
        let writer_id = id.clone();
        std::thread::spawn(move || {
            let mut writer = writer;
            while let Some(data) = writer_rx.blocking_recv() {
                if let Err(e) = writer.write_all(&data) {
                    warn!(session = %writer_id, error = %e, "PTY writer error");
                    break;
                }
                let _ = writer.flush();
            }
        });

        Ok((
            Self {
                id,
                writer_tx,
                master: pair.master,
                child,
            },
            output_rx,
        ))
    }

    pub fn write_input(&self, data: &[u8]) -> Result<()> {
        self.writer_tx
            .send(data.to_vec())
            .map_err(|_| anyhow::anyhow!("PTY writer channel closed"))?;
        Ok(())
    }

    pub fn resize(&self, cols: u16, rows: u16) -> Result<()> {
        self.master.resize(PtySize {
            rows,
            cols,
            pixel_width: 0,
            pixel_height: 0,
        })?;
        Ok(())
    }

    pub fn is_alive(&mut self) -> bool {
        self.child.try_wait().ok().flatten().is_none()
    }

    pub fn try_exit_code(&mut self) -> Option<u32> {
        self.child
            .try_wait()
            .ok()
            .flatten()
            .and_then(|s| Some(s.exit_code()))
    }

    pub fn kill(&mut self) {
        let _ = self.child.kill();
    }
}

impl Drop for PtySession {
    fn drop(&mut self) {
        self.kill();
    }
}

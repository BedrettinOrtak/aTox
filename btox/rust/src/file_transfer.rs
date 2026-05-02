// btox_core/src/file_transfer.rs
//
// 10 GB+ dosyalar için chunk-based transfer iskeleti.
// toxcore'un tox_file_send API'si u64 boyut destekler ve chunk'ları
// callback ile ister; biz seek+read ile besleriz, dosyayı belleğe yüklemeyiz.

use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;

use anyhow::{anyhow, Context, Result};
use once_cell::sync::Lazy;
use tokio::fs::File;
use tokio::io::{AsyncReadExt, AsyncSeekExt, SeekFrom};
use tokio::sync::{broadcast, Mutex};

use crate::tox_core::ToxCore;
use crate::BtoxEvent;

const PROGRESS_INTERVAL_BYTES: u64 = 64 * 1024;

#[derive(Clone)]
struct Transfer {
    file: Arc<Mutex<File>>,
    total: u64,
    transferred: u64,
    paused: bool,
    cancelled: bool,
}

static TRANSFERS: Lazy<Mutex<HashMap<(u32, u32), Transfer>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

pub async fn send_file(core: &ToxCore, friend_id: u32, path: &str) -> Result<u32> {
    let p = Path::new(path);
    let meta = tokio::fs::metadata(p).await
        .with_context(|| format!("dosya bulunamadı: {path}"))?;
    let total = meta.len();
    let _name = p.file_name().and_then(|s| s.to_str())
        .ok_or_else(|| anyhow!("dosya adı geçersiz"))?
        .to_string();

    // TODO real-tox: tox_file_send(friend_id, KIND_DATA, total, file_id, name)
    let file_id = next_file_id();

    let file = File::open(p).await?;
    TRANSFERS.lock().await.insert(
        (friend_id, file_id),
        Transfer {
            file: Arc::new(Mutex::new(file)),
            total,
            transferred: 0,
            paused: false,
            cancelled: false,
        },
    );

    log::info!(
        "send_file -> friend={friend_id}, file_id={file_id}, total={total} B ({:.2} GB)",
        total as f64 / (1024.0 * 1024.0 * 1024.0)
    );

    spawn_pump(core.events_sender(), friend_id, file_id);
    Ok(file_id)
}

pub async fn pause(_core: &ToxCore, friend_id: u32, file_id: u32) -> Result<()> {
    if let Some(t) = TRANSFERS.lock().await.get_mut(&(friend_id, file_id)) {
        t.paused = true;
    }
    Ok(())
}

pub async fn resume(_core: &ToxCore, friend_id: u32, file_id: u32) -> Result<()> {
    if let Some(t) = TRANSFERS.lock().await.get_mut(&(friend_id, file_id)) {
        t.paused = false;
    }
    Ok(())
}

pub async fn cancel(_core: &ToxCore, friend_id: u32, file_id: u32) -> Result<()> {
    TRANSFERS.lock().await.remove(&(friend_id, file_id));
    Ok(())
}

fn spawn_pump(events: broadcast::Sender<BtoxEvent>, friend_id: u32, file_id: u32) {
    tokio::spawn(async move {
        let mut last_reported: u64 = 0;
        loop {
            let snap = TRANSFERS.lock().await.get(&(friend_id, file_id)).cloned();
            let Some(t) = snap else { return; };
            if t.cancelled { return; }

            if t.paused {
                tokio::time::sleep(std::time::Duration::from_millis(200)).await;
                continue;
            }
            if t.transferred >= t.total {
                let _ = events.send(BtoxEvent::FileProgress {
                    friend_id, file_id,
                    transferred: t.total, total: t.total,
                });
                TRANSFERS.lock().await.remove(&(friend_id, file_id));
                return;
            }

            let to_read = PROGRESS_INTERVAL_BYTES.min(t.total - t.transferred) as usize;
            let mut buf = vec![0u8; to_read];
            {
                let mut f = t.file.lock().await;
                if let Err(e) = f.seek(SeekFrom::Start(t.transferred)).await {
                    log::error!("seek: {e}");
                    return;
                }
                if let Err(e) = f.read_exact(&mut buf).await {
                    log::error!("read: {e}");
                    return;
                }
            }
            // TODO real-tox: toxcore'a chunk besle (1371 B'lık parçalara böl).

            let new_transferred = t.transferred + to_read as u64;
            if let Some(slot) = TRANSFERS.lock().await.get_mut(&(friend_id, file_id)) {
                slot.transferred = new_transferred;
            }

            if new_transferred - last_reported >= PROGRESS_INTERVAL_BYTES
                || new_transferred == t.total
            {
                last_reported = new_transferred;
                let _ = events.send(BtoxEvent::FileProgress {
                    friend_id, file_id,
                    transferred: new_transferred,
                    total: t.total,
                });
            }
        }
    });
}

fn next_file_id() -> u32 {
    use std::sync::atomic::{AtomicU32, Ordering};
    static N: AtomicU32 = AtomicU32::new(1);
    N.fetch_add(1, Ordering::Relaxed)
}

#[cfg(test)]
mod tests {
    use super::PROGRESS_INTERVAL_BYTES;

    #[test]
    fn progress_interval_is_64k() {
        assert_eq!(PROGRESS_INTERVAL_BYTES, 65536);
    }

    #[test]
    fn ten_gb_progress_count() {
        let ten_gb: u64 = 10 * 1024 * 1024 * 1024;
        assert!(ten_gb < u64::MAX);
        let reports = ten_gb / PROGRESS_INTERVAL_BYTES;
        assert_eq!(reports, 10 * 1024 * 16);
    }

    #[test]
    fn next_file_id_is_monotonic() {
        let a = super::next_file_id();
        let b = super::next_file_id();
        assert!(b > a);
    }
}


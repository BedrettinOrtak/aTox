// btox_core/src/messaging.rs
//
// P2P metin mesajlaşma. toxcore mesaj boyutu sınırını (TOX_MAX_MESSAGE_LENGTH = 1372 B)
// otomatik olarak parçalar.

use anyhow::Result;

use crate::tox_core::ToxCore;
use crate::{BtoxEvent, ChatMessage};

const TOX_MAX_MESSAGE_LENGTH: usize = 1372;

pub async fn send_text(core: &ToxCore, friend_id: u32, text: &str) -> Result<()> {
    let bytes = text.as_bytes();
    if bytes.is_empty() {
        return Ok(());
    }

    // UTF-8 sınırlarını koruyarak parçala
    let mut start = 0;
    while start < bytes.len() {
        let mut end = (start + TOX_MAX_MESSAGE_LENGTH).min(bytes.len());
        // UTF-8 char sınırına kadar geri al
        while end > start && !text.is_char_boundary(end) {
            end -= 1;
        }
        let chunk = &text[start..end];
        // TODO: tox_friend_send_message(friend_id, NORMAL, chunk)
        log::debug!("send_text -> friend={friend_id}, len={}", chunk.len());
        start = end;
    }

    // Yerel olarak da olay olarak yay (UI hemen göstersin)
    let now = chrono_now_ms();
    let _ = core.events_sender().send(BtoxEvent::Message(ChatMessage {
        friend_id,
        text: text.to_string(),
        outgoing: true,
        timestamp_ms: now,
    }));

    Ok(())
}

fn chrono_now_ms() -> i64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}


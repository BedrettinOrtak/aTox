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

#[cfg(test)]
mod tests {
    use super::TOX_MAX_MESSAGE_LENGTH;

    /// Üretim kodundaki chunklama mantığını saf fonksiyon olarak çoğalt:
    /// UTF-8 sınırlarını koruyarak parçala.
    fn chunk_utf8(text: &str) -> Vec<&str> {
        let bytes = text.as_bytes();
        let mut out = Vec::new();
        let mut start = 0;
        while start < bytes.len() {
            let mut end = (start + TOX_MAX_MESSAGE_LENGTH).min(bytes.len());
            while end > start && !text.is_char_boundary(end) {
                end -= 1;
            }
            out.push(&text[start..end]);
            start = end;
        }
        out
    }

    #[test]
    fn empty_input_yields_no_chunks() {
        assert!(chunk_utf8("").is_empty());
    }

    #[test]
    fn short_message_is_one_chunk() {
        let chunks = chunk_utf8("merhaba");
        assert_eq!(chunks.len(), 1);
        assert_eq!(chunks[0], "merhaba");
    }

    #[test]
    fn splits_by_max_length() {
        let s = "a".repeat(TOX_MAX_MESSAGE_LENGTH * 3);
        let chunks = chunk_utf8(&s);
        assert_eq!(chunks.len(), 3);
        for c in &chunks {
            assert!(c.len() <= TOX_MAX_MESSAGE_LENGTH);
        }
    }

    #[test]
    fn never_splits_in_middle_of_utf8_codepoint() {
        // 'ş' = 2 byte. TOX_MAX_MESSAGE_LENGTH'in tam ortasına denk gelecek
        // şekilde Türkçe karakterlerden oluşan bir string oluştur.
        let s: String = std::iter::repeat('ş').take(TOX_MAX_MESSAGE_LENGTH).collect();
        let chunks = chunk_utf8(&s);
        // Hiçbir parça invalid UTF-8 olmamalı (zaten &str olduğu için Rust derlerken
        // garanti eder; ama parçaların birleşimi orijinali vermeli):
        let joined: String = chunks.concat();
        assert_eq!(joined, s);
    }

    #[test]
    fn chunks_concat_to_original() {
        let s = "Hello 🌍! ".repeat(500);
        let chunks = chunk_utf8(&s);
        let joined: String = chunks.concat();
        assert_eq!(joined, s);
    }
}

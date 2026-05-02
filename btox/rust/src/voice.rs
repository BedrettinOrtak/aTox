// btox_core/src/voice.rs
//
// Push-to-talk: 48 kHz mono 16-bit PCM çerçevelerini Opus ile kodlayıp
// ToxAV ses kanalı üzerinden gönderir.
// Çerçeve süresi: 20 ms  ->  48000 * 0.020 = 960 örnek.
// Opus encoder `ptt-opus` feature'ı ile aktifleşir.

use std::collections::HashMap;
use std::sync::Mutex;

use anyhow::{anyhow, Result};
use once_cell::sync::Lazy;

#[cfg(feature = "ptt-opus")]
use opus::{Application, Channels, Encoder};

use crate::tox_core::ToxCore;

const SAMPLE_RATE: u32 = 48_000;
const FRAME_SAMPLES: usize = 960; // 20 ms @ 48 kHz mono
#[cfg(feature = "ptt-opus")]
const MAX_OPUS_PACKET: usize = 1276;

struct PttSession {
    #[cfg(feature = "ptt-opus")]
    encoder: Encoder,
}

static SESSIONS: Lazy<Mutex<HashMap<u32, PttSession>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

pub async fn start_ptt(_core: &ToxCore, friend_id: u32) -> Result<()> {
    #[cfg(feature = "ptt-opus")]
    let session = {
        let encoder = Encoder::new(SAMPLE_RATE, Channels::Mono, Application::Voip)
            .map_err(|e| anyhow!("opus encoder oluşturulamadı: {e}"))?;
        PttSession { encoder }
    };
    #[cfg(not(feature = "ptt-opus"))]
    let session = PttSession {};

    SESSIONS.lock().unwrap().insert(friend_id, session);
    let _ = SAMPLE_RATE;
    // TODO real-tox: toxav_call(audio_bit_rate=32000, video_bit_rate=0)
    log::info!("PTT başladı -> friend={friend_id}");
    Ok(())
}

pub async fn push_frame(_core: &ToxCore, friend_id: u32, pcm: &[i16]) -> Result<()> {
    if pcm.len() != FRAME_SAMPLES {
        return Err(anyhow!(
            "PCM çerçeve {} örnek olmalı (verilen: {})",
            FRAME_SAMPLES, pcm.len()
        ));
    }
    let mut sessions = SESSIONS.lock().unwrap();
    let _session = sessions.get_mut(&friend_id)
        .ok_or_else(|| anyhow!("PTT oturumu yok — önce ptt_start çağır"))?;

    #[cfg(feature = "ptt-opus")]
    {
        let mut out = vec![0u8; MAX_OPUS_PACKET];
        let written = _session.encoder.encode(pcm, &mut out)
            .map_err(|e| anyhow!("opus encode hata: {e}"))?;
        out.truncate(written);
        // TODO real-tox: toxav_audio_send_frame(...)
        log::trace!("PTT frame -> friend={friend_id}, opus_bytes={written}");
    }

    #[cfg(not(feature = "ptt-opus"))]
    {
        log::trace!("PTT frame (raw) -> friend={friend_id}, pcm_samples={}", pcm.len());
    }

    Ok(())
}

pub async fn stop_ptt(_core: &ToxCore, friend_id: u32) -> Result<()> {
    SESSIONS.lock().unwrap().remove(&friend_id);
    log::info!("PTT bitti -> friend={friend_id}");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frame_size_matches_20ms_at_48khz() {
        assert_eq!(FRAME_SAMPLES, (SAMPLE_RATE as usize / 1000) * 20);
    }
}


// btox_core/src/lib.rs
//
// BTOX Rust çekirdeği — flutter_rust_bridge tarafından Flutter'a açılan API.
//
// Mimari:
//   - `tox_core`        : Tox kimlik (ID), arkadaşlık istekleri, P2P bağlantı
//   - `messaging`       : P2P metin mesajlaşma
//   - `voice`           : Push-to-talk (Opus + ToxAV)
//   - `file_transfer`   : 10 GB+ dosyalar için chunk-based transfer
//
// Bu dosya yalnızca dış API'yi (Flutter'a açılan fonksiyonlar) tanımlar.
// Detaylar alt modüllerde.

#![allow(clippy::needless_return)]

use std::sync::OnceLock;

use anyhow::Result;
use flutter_rust_bridge::frb;
use tokio::sync::Mutex;

pub mod tox_core;
pub mod messaging;
pub mod voice;
pub mod file_transfer;

use tox_core::ToxCore;

// ---------------------------------------------------------------------------
// Global runtime + tek bir çekirdek örneği.
// Mobil tarafta tek bir Tox profili açık olur; bu yüzden global tutuyoruz.
// ---------------------------------------------------------------------------

static CORE: OnceLock<Mutex<Option<ToxCore>>> = OnceLock::new();

fn core() -> &'static Mutex<Option<ToxCore>> {
    CORE.get_or_init(|| Mutex::new(None))
}

// ---------------------------------------------------------------------------
// DTO'lar — flutter_rust_bridge bunları otomatik olarak Dart sınıflarına çevirir.
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct Friend {
    pub id: u32,
    pub tox_id: String,        // 76 hex
    pub name: String,
    pub status_message: String,
    pub online: bool,
}

#[derive(Debug, Clone)]
pub struct ChatMessage {
    pub friend_id: u32,
    pub text: String,
    pub outgoing: bool,
    pub timestamp_ms: i64,
}

#[derive(Debug, Clone)]
pub enum BtoxEvent {
    /// Bağlantı durumu değişti (DHT)
    ConnectionChanged { online: bool },
    /// Yeni arkadaşlık isteği geldi
    FriendRequest { tox_id: String, message: String },
    /// Arkadaş listesi güncellendi
    FriendUpdated(Friend),
    /// Yeni mesaj geldi
    Message(ChatMessage),
    /// Dosya transferi ilerlemesi
    FileProgress {
        friend_id: u32,
        file_id: u32,
        transferred: u64,
        total: u64,
    },
    /// Sesli mesaj parçası geldi (PTT)
    VoiceFrame { friend_id: u32, pcm: Vec<i16> },
}

// ---------------------------------------------------------------------------
// PUBLIC API — Flutter'dan çağrılan fonksiyonlar
// ---------------------------------------------------------------------------

/// Logger'ı başlat. Android'de logcat'a yazar.
pub fn init_logger() {
    #[cfg(target_os = "android")]
    {
        let _ = android_logger::init_once(
            android_logger::Config::default()
                .with_max_level(log::LevelFilter::Info)
                .with_tag("btox"),
        );
    }
    #[cfg(not(target_os = "android"))]
    {
        let _ = env_logger::builder().filter_level(log::LevelFilter::Info).try_init();
    }
    log::info!("btox_core logger initialized");
}

/// Yeni profil oluştur veya mevcut profili `data_dir` altından yükle.
/// Dönüş: kendi Tox ID'miz (76 hex).
pub async fn start(data_dir: String, profile_name: String) -> Result<String> {
    let mut guard = core().lock().await;
    if guard.is_some() {
        anyhow::bail!("BTOX zaten çalışıyor");
    }
    let core = ToxCore::start(&data_dir, &profile_name).await?;
    let tox_id = core.self_tox_id();
    *guard = Some(core);
    log::info!("BTOX started, tox_id={}", tox_id);
    Ok(tox_id)
}

/// Olay akışı — Dart tarafında `Stream<BtoxEvent>` olur.
pub async fn event_stream(sink: flutter_rust_bridge::StreamSink<BtoxEvent>) -> Result<()> {
    let guard = core().lock().await;
    let core = guard.as_ref().ok_or_else(|| anyhow::anyhow!("start() çağrılmadı"))?;
    core.subscribe_events(sink).await;
    Ok(())
}

// --- Kimlik / Arkadaşlık ---------------------------------------------------

pub async fn self_tox_id() -> Result<String> {
    let guard = core().lock().await;
    Ok(guard.as_ref().ok_or_else(|| anyhow::anyhow!("not started"))?.self_tox_id())
}

pub async fn set_self_name(name: String) -> Result<()> {
    let mut guard = core().lock().await;
    guard.as_mut().ok_or_else(|| anyhow::anyhow!("not started"))?.set_name(&name).await
}

/// `tox_id`: 76 hex karakter (qTox ile aynı format).
/// `message`: arkadaşlık isteği mesajı.
pub async fn add_friend(tox_id: String, message: String) -> Result<u32> {
    let mut guard = core().lock().await;
    guard.as_mut().ok_or_else(|| anyhow::anyhow!("not started"))?
        .add_friend(&tox_id, &message).await
}

pub async fn accept_friend_request(tox_id: String) -> Result<u32> {
    let mut guard = core().lock().await;
    guard.as_mut().ok_or_else(|| anyhow::anyhow!("not started"))?
        .accept_friend_request(&tox_id).await
}

pub async fn list_friends() -> Result<Vec<Friend>> {
    let guard = core().lock().await;
    Ok(guard.as_ref().ok_or_else(|| anyhow::anyhow!("not started"))?.list_friends())
}

// --- Mesajlaşma ------------------------------------------------------------

pub async fn send_message(friend_id: u32, text: String) -> Result<()> {
    let guard = core().lock().await;
    let core = guard.as_ref().ok_or_else(|| anyhow::anyhow!("not started"))?;
    messaging::send_text(core, friend_id, &text).await
}

// --- Push-to-talk ----------------------------------------------------------

pub async fn ptt_start(friend_id: u32) -> Result<()> {
    let guard = core().lock().await;
    let core = guard.as_ref().ok_or_else(|| anyhow::anyhow!("not started"))?;
    voice::start_ptt(core, friend_id).await
}

/// 20 ms'lik PCM 16-bit mono 48 kHz çerçevesi (= 960 örnek). Encoder Opus'a çevirir.
pub async fn ptt_push_frame(friend_id: u32, pcm: Vec<i16>) -> Result<()> {
    let guard = core().lock().await;
    let core = guard.as_ref().ok_or_else(|| anyhow::anyhow!("not started"))?;
    voice::push_frame(core, friend_id, &pcm).await
}

pub async fn ptt_stop(friend_id: u32) -> Result<()> {
    let guard = core().lock().await;
    let core = guard.as_ref().ok_or_else(|| anyhow::anyhow!("not started"))?;
    voice::stop_ptt(core, friend_id).await
}

// --- Dosya transferi (chunk-based, 10 GB+) --------------------------------

pub async fn send_file(friend_id: u32, path: String) -> Result<u32> {
    let guard = core().lock().await;
    let core = guard.as_ref().ok_or_else(|| anyhow::anyhow!("not started"))?;
    file_transfer::send_file(core, friend_id, &path).await
}

pub async fn cancel_file(friend_id: u32, file_id: u32) -> Result<()> {
    let guard = core().lock().await;
    let core = guard.as_ref().ok_or_else(|| anyhow::anyhow!("not started"))?;
    file_transfer::cancel(core, friend_id, file_id).await
}

pub async fn pause_file(friend_id: u32, file_id: u32) -> Result<()> {
    let guard = core().lock().await;
    let core = guard.as_ref().ok_or_else(|| anyhow::anyhow!("not started"))?;
    file_transfer::pause(core, friend_id, file_id).await
}

pub async fn resume_file(friend_id: u32, file_id: u32) -> Result<()> {
    let guard = core().lock().await;
    let core = guard.as_ref().ok_or_else(|| anyhow::anyhow!("not started"))?;
    file_transfer::resume(core, friend_id, file_id).await
}


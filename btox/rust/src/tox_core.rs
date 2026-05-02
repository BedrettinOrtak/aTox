// btox_core/src/tox_core.rs
//
// Tox çekirdeği sarmalayıcısı. `real-tox` feature'ı açıkken `rstox` (c-toxcore
// FFI) ile gerçek protokol çalışır; kapalıyken her şey in-memory stub'tır
// (UI iskeleti bağımsız test edilebilir).

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;

use anyhow::{anyhow, Context, Result};
use flutter_rust_bridge::StreamSink;
use tokio::sync::{broadcast, RwLock};

use crate::{BtoxEvent, Friend};

// Bootstrap düğümleri — qTox ile aynı liste.
const BOOTSTRAP_NODES: &[(&str, u16, &str)] = &[
    ("85.143.221.42",     33445, "DA4E4ED4B697F2E9B000EEFE3A34B554ACD3F45F5C96EAEA2516DD7FF9AF7B43"),
    ("78.46.73.141",      33445, "02807CF4F8BB8FB390CC3794BDF1E8449E9A8392C5D3F2200019DA9F1E812E46"),
    ("tox.verdict.gg",    33445, "1C5293AEF2114717547B39DA8EA6F1E331E5E358B35F9B6B5F19317911C5F976"),
    ("tox.abilinski.com", 33445, "10C00EB250C3233E343E2AEBA07115A5C28920E9C8D29492F6D00B29049EDC7E"),
];

// ---------------------------------------------------------------------------
// Gerçek arka uç (opsiyonel)
// ---------------------------------------------------------------------------

#[cfg(feature = "real-tox")]
mod backend {
    use anyhow::{anyhow, Context, Result};
    use rstox::core::{Tox, ToxOptions};
    use std::path::Path;

    pub struct Backend { pub tox: Tox }

    impl Backend {
        pub fn open_or_create(profile: &Path) -> Result<Self> {
            let mut opts = ToxOptions::new();
            opts.ipv6_enabled(true);
            opts.udp_enabled(true);

            let tox = if profile.exists() {
                let bytes = std::fs::read(profile)
                    .with_context(|| format!("profil okunamadı: {}", profile.display()))?;
                Tox::new(opts, Some(&bytes)).map_err(|e| anyhow!("tox load: {e:?}"))?
            } else {
                Tox::new(opts, None).map_err(|e| anyhow!("tox new: {e:?}"))?
            };
            Ok(Self { tox })
        }

        pub fn save(&self, profile: &Path) -> Result<()> {
            std::fs::write(profile, self.tox.save())?;
            Ok(())
        }

        pub fn self_address_hex(&self) -> String {
            format!("{}", self.tox.get_address())
        }
    }
}

// ---------------------------------------------------------------------------

pub struct ToxCore {
    #[allow(dead_code)]
    profile_path: PathBuf,
    self_tox_id_hex: String,
    self_name: Arc<RwLock<String>>,
    friends: Arc<RwLock<HashMap<u32, Friend>>>,
    events_tx: broadcast::Sender<BtoxEvent>,
}

impl ToxCore {
    pub async fn start(data_dir: &str, profile_name: &str) -> Result<Self> {
        let mut profile_path = PathBuf::from(data_dir);
        tokio::fs::create_dir_all(&profile_path).await
            .with_context(|| format!("data_dir oluşturulamadı: {data_dir}"))?;
        profile_path.push(format!("{profile_name}.tox"));

        log::info!("toxcore başlatılıyor: {}", profile_path.display());

        #[cfg(feature = "real-tox")]
        let self_tox_id_hex = {
            let backend = backend::Backend::open_or_create(&profile_path)?;
            for (host, port, pk_hex) in BOOTSTRAP_NODES {
                if let Ok(pk) = hex::decode(pk_hex) {
                    let _ = backend.tox.bootstrap(host, *port, &pk);
                }
            }
            let id = backend.self_address_hex();
            let _ = backend.save(&profile_path);
            // TODO: backend'i global slot'a koyup iterate loop'a bağla.
            id
        };

        #[cfg(not(feature = "real-tox"))]
        let self_tox_id_hex = "0".repeat(76);

        let (events_tx, _rx) = broadcast::channel::<BtoxEvent>(256);

        let core = Self {
            profile_path,
            self_tox_id_hex,
            self_name: Arc::new(RwLock::new(String::new())),
            friends: Arc::new(RwLock::new(HashMap::new())),
            events_tx,
        };
        core.spawn_iterate_loop();
        Ok(core)
    }

    fn spawn_iterate_loop(&self) {
        let tx = self.events_tx.clone();
        tokio::spawn(async move {
            // TODO real-tox: ~50 ms periyodla tox_iterate, callback'ler -> BtoxEvent
            tokio::time::sleep(std::time::Duration::from_millis(500)).await;
            let _ = tx.send(BtoxEvent::ConnectionChanged { online: true });
        });
    }

    pub fn self_tox_id(&self) -> String { self.self_tox_id_hex.clone() }

    pub async fn set_name(&mut self, name: &str) -> Result<()> {
        // TODO real-tox: tox_self_set_name
        *self.self_name.write().await = name.to_string();
        Ok(())
    }

    pub async fn add_friend(&mut self, tox_id_hex: &str, message: &str) -> Result<u32> {
        validate_tox_id(tox_id_hex)?;
        // TODO real-tox: tox_friend_add(tox_id, message)
        let id = self.next_friend_id().await;
        let f = Friend {
            id,
            tox_id: tox_id_hex.to_string(),
            name: String::new(),
            status_message: format!("istek: {message}"),
            online: false,
        };
        self.friends.write().await.insert(id, f.clone());
        let _ = self.events_tx.send(BtoxEvent::FriendUpdated(f));
        Ok(id)
    }

    pub async fn accept_friend_request(&mut self, tox_id_hex: &str) -> Result<u32> {
        validate_tox_id(tox_id_hex)?;
        // TODO real-tox: tox_friend_add_norequest(public_key)
        let id = self.next_friend_id().await;
        let f = Friend {
            id,
            tox_id: tox_id_hex.to_string(),
            name: String::new(),
            status_message: String::new(),
            online: false,
        };
        self.friends.write().await.insert(id, f.clone());
        let _ = self.events_tx.send(BtoxEvent::FriendUpdated(f));
        Ok(id)
    }

    pub fn list_friends(&self) -> Vec<Friend> {
        self.friends.try_read().map(|m| m.values().cloned().collect()).unwrap_or_default()
    }

    async fn next_friend_id(&self) -> u32 {
        self.friends.read().await.len() as u32
    }

    pub async fn subscribe_events(&self, sink: StreamSink<BtoxEvent>) {
        let mut rx = self.events_tx.subscribe();
        tokio::spawn(async move {
            while let Ok(ev) = rx.recv().await {
                if !sink.add(ev) { break; }
            }
        });
    }

    pub fn events_sender(&self) -> broadcast::Sender<BtoxEvent> {
        self.events_tx.clone()
    }
}

fn validate_tox_id(s: &str) -> Result<()> {
    if s.len() != 76 {
        return Err(anyhow!("Tox ID 76 hex karakter olmalı (verilen: {})", s.len()));
    }
    hex::decode(s).map_err(|e| anyhow!("geçersiz hex: {e}"))?;
    Ok(())
}


use anyhow::{anyhow, Context, Result};
use aws_credential_types::Credentials;
use aws_sdk_s3::config::{BehaviorVersion, Region};
use aws_sdk_s3::primitives::ByteStream;
use aws_sdk_s3::Client;
use std::path::Path;
use time::format_description::well_known::Rfc3339;
use tokio::sync::mpsc;
use tracing::{error, info, warn};

use crate::manifest::{day_archive_key, Manifest, Segment};
use crate::writer::FinishedSegment;
use crate::Args;

const ROLLING_KEEP: usize = 24 * 60; // 24h at one segment per minute
const INDEX_KEY: &str = "index.json";

pub struct R2Config {
    pub account_id: String,
    pub access_key_id: String,
    pub secret_access_key: String,
    pub bucket: String,
    pub public_base_url: String,
    pub key_prefix: String,
}

impl R2Config {
    pub fn from_args(args: &Args) -> Result<Self> {
        let need = |opt: &Option<String>, name: &str| -> Result<String> {
            opt.clone()
                .ok_or_else(|| anyhow!("missing required R2 setting: {name}"))
        };
        Ok(R2Config {
            account_id: need(&args.r2_account_id, "R2_ACCOUNT_ID")?,
            access_key_id: need(&args.r2_access_key_id, "R2_ACCESS_KEY_ID")?,
            secret_access_key: need(&args.r2_secret_access_key, "R2_SECRET_ACCESS_KEY")?,
            bucket: need(&args.r2_bucket, "R2_BUCKET")?,
            public_base_url: need(&args.r2_public_base_url, "R2_PUBLIC_BASE_URL")?
                .trim_end_matches('/')
                .to_string(),
            key_prefix: args.key_prefix.trim_matches('/').to_string(),
        })
    }
}

pub struct Uploader {
    client: Client,
    cfg: R2Config,
    rolling: Manifest,
}

impl Uploader {
    pub async fn new(cfg: R2Config) -> Result<Self> {
        let endpoint = format!("https://{}.r2.cloudflarestorage.com", cfg.account_id);
        let creds = Credentials::new(
            &cfg.access_key_id,
            &cfg.secret_access_key,
            None,
            None,
            "mic-recorder",
        );
        let aws_cfg = aws_config::defaults(BehaviorVersion::latest())
            .region(Region::new("auto"))
            .endpoint_url(endpoint)
            .credentials_provider(creds)
            .load()
            .await;
        let s3_cfg = aws_sdk_s3::config::Builder::from(&aws_cfg)
            .force_path_style(true)
            .build();
        let client = Client::from_conf(s3_cfg);

        // Try to seed the rolling manifest from whatever's already in the bucket
        // so a restart doesn't drop history that listeners might still want.
        let rolling = match fetch_json::<Manifest>(&client, &cfg.bucket, INDEX_KEY).await {
            Ok(Some(m)) => {
                info!("loaded existing index.json with {} segments", m.segments.len());
                m
            }
            Ok(None) => Manifest::default(),
            Err(e) => {
                warn!("failed to load existing index.json (continuing fresh): {e:#}");
                Manifest::default()
            }
        };

        Ok(Self { client, cfg, rolling })
    }

    pub async fn upload_segment(&mut self, finished: &FinishedSegment) -> Result<Segment> {
        let key = build_key(&self.cfg.key_prefix, finished);
        let body = ByteStream::from_path(&finished.local_path)
            .await
            .with_context(|| format!("reading {:?}", finished.local_path))?;

        self.client
            .put_object()
            .bucket(&self.cfg.bucket)
            .key(&key)
            .content_type("audio/wav")
            .body(body)
            .send()
            .await
            .with_context(|| format!("PutObject {key}"))?;

        let seg = Segment {
            url: format!("{}/{}", self.cfg.public_base_url, key),
            key,
            started_at: finished.started_at.format(&Rfc3339).unwrap_or_default(),
            duration_seconds: finished.duration_seconds,
            size_bytes: finished.size_bytes,
            sample_rate: finished.sample_rate,
            channels: finished.channels,
        };
        Ok(seg)
    }

    async fn update_manifests(&mut self, seg: Segment) -> Result<()> {
        // Rolling 24h index.
        self.rolling.push_trimmed(seg.clone(), ROLLING_KEEP);
        put_json(&self.client, &self.cfg.bucket, INDEX_KEY, &self.rolling)
            .await
            .context("writing index.json")?;

        // Per-day archive: read-modify-write. Single-writer, so no contention.
        let date = time::OffsetDateTime::parse(&seg.started_at, &Rfc3339)
            .map(|d| d.date())
            .unwrap_or_else(|_| time::OffsetDateTime::now_utc().date());
        let day_key = day_archive_key(date);
        let mut day = fetch_json::<Manifest>(&self.client, &self.cfg.bucket, &day_key)
            .await
            .ok()
            .flatten()
            .unwrap_or_default();
        day.append(seg);
        put_json(&self.client, &self.cfg.bucket, &day_key, &day)
            .await
            .with_context(|| format!("writing {day_key}"))?;
        Ok(())
    }
}

fn build_key(prefix: &str, finished: &FinishedSegment) -> String {
    let t = finished.started_at;
    let filename = format!(
        "{:04}-{:02}-{:02}T{:02}-{:02}-{:02}Z.wav",
        t.year(),
        u8::from(t.month()),
        t.day(),
        t.hour(),
        t.minute(),
        t.second(),
    );
    format!(
        "{}/{:04}/{:02}/{:02}/{}",
        prefix.trim_matches('/'),
        t.year(),
        u8::from(t.month()),
        t.day(),
        filename
    )
}

async fn fetch_json<T: serde::de::DeserializeOwned>(
    client: &Client,
    bucket: &str,
    key: &str,
) -> Result<Option<T>> {
    match client.get_object().bucket(bucket).key(key).send().await {
        Ok(resp) => {
            let bytes = resp
                .body
                .collect()
                .await
                .with_context(|| format!("reading body of {key}"))?
                .into_bytes();
            let parsed = serde_json::from_slice(&bytes)
                .with_context(|| format!("parsing JSON at {key}"))?;
            Ok(Some(parsed))
        }
        Err(e) => {
            // NoSuchKey is expected on first run; treat as None.
            let msg = format!("{e}");
            if msg.contains("NoSuchKey") || msg.contains("404") {
                return Ok(None);
            }
            Err(anyhow!("GetObject {key}: {e}"))
        }
    }
}

async fn put_json<T: serde::Serialize>(
    client: &Client,
    bucket: &str,
    key: &str,
    value: &T,
) -> Result<()> {
    let body = serde_json::to_vec_pretty(value).context("serializing manifest")?;
    client
        .put_object()
        .bucket(bucket)
        .key(key)
        .content_type("application/json")
        .body(ByteStream::from(body))
        .send()
        .await
        .with_context(|| format!("PutObject {key}"))?;
    Ok(())
}

/// Drains finished segments until the channel closes.
pub async fn run(
    mut uploader: Option<Uploader>,
    mut rx: mpsc::Receiver<FinishedSegment>,
    keep_local: bool,
) -> Result<()> {
    while let Some(finished) = rx.recv().await {
        let local_path = finished.local_path.clone();
        if let Some(up) = uploader.as_mut() {
            match up.upload_segment(&finished).await {
                Ok(seg) => {
                    info!("uploaded {} ({} bytes)", seg.key, seg.size_bytes);
                    if let Err(e) = up.update_manifests(seg).await {
                        error!("manifest update failed: {e:#}");
                    }
                    if !keep_local {
                        delete_local(&local_path);
                    }
                }
                Err(e) => {
                    // Don't delete local on failure; operator can retry by hand.
                    error!("upload failed for {local_path:?}: {e:#}");
                }
            }
        } else {
            // dry-run: nothing to do; local file is the artifact.
            info!("dry-run: kept local {:?}", local_path);
        }
    }
    info!("uploader loop exited");
    Ok(())
}

fn delete_local(path: &Path) {
    if let Err(e) = std::fs::remove_file(path) {
        warn!("failed to delete local file {path:?}: {e}");
    }
}

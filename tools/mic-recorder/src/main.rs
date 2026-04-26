use anyhow::{Context, Result};
use clap::Parser;
use std::path::PathBuf;
use tokio::sync::mpsc;
use tracing::{error, info};

mod capture;
mod manifest;
mod upload;
mod writer;

#[derive(Parser, Debug, Clone)]
#[command(name = "mic-recorder", about = "Continuous USB mic recorder with R2 upload")]
struct Args {
    /// List input devices and exit.
    #[arg(long)]
    list_devices: bool,

    /// Substring of input device name. Default: system default input.
    #[arg(long)]
    device: Option<String>,

    /// Seconds per recorded chunk before rotating to a new file.
    #[arg(long, default_value_t = 60)]
    rotation_seconds: u64,

    /// Local directory to buffer WAV files into before upload.
    #[arg(long, default_value = "recordings")]
    output_dir: PathBuf,

    /// Keep local WAV files after a successful upload (default: delete).
    #[arg(long)]
    keep_local: bool,

    /// Skip R2 upload entirely; write local files only.
    #[arg(long)]
    dry_run: bool,

    /// Object key prefix in the bucket.
    #[arg(long, default_value = "audio")]
    key_prefix: String,

    // R2 config (only required when not --dry-run).
    #[arg(long, env = "R2_ACCOUNT_ID")]
    r2_account_id: Option<String>,
    #[arg(long, env = "R2_ACCESS_KEY_ID")]
    r2_access_key_id: Option<String>,
    #[arg(long, env = "R2_SECRET_ACCESS_KEY")]
    r2_secret_access_key: Option<String>,
    #[arg(long, env = "R2_BUCKET")]
    r2_bucket: Option<String>,
    /// Public base URL for objects (no trailing slash). Used to populate the manifest.
    #[arg(long, env = "R2_PUBLIC_BASE_URL")]
    r2_public_base_url: Option<String>,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info,mic_recorder=debug")),
        )
        .init();

    let args = Args::parse();

    if args.list_devices {
        capture::list_devices()?;
        return Ok(());
    }

    tokio::fs::create_dir_all(&args.output_dir)
        .await
        .with_context(|| format!("creating output dir {:?}", args.output_dir))?;

    // Channel: writer -> uploader. Bounded so disk doesn't outpace network forever.
    let (finished_tx, finished_rx) = mpsc::channel::<writer::FinishedSegment>(64);

    // Build R2 client only if we'll actually upload.
    let uploader = if args.dry_run {
        info!("dry-run mode: skipping R2 upload");
        None
    } else {
        let cfg = upload::R2Config::from_args(&args)
            .context("R2 configuration missing; pass --dry-run or set R2_* env vars")?;
        Some(upload::Uploader::new(cfg).await?)
    };

    // Spawn uploader task.
    let upload_handle = tokio::spawn(upload::run(uploader, finished_rx, args.keep_local));

    // Capture + writer run on a dedicated OS thread (cpal Stream is !Send).
    let capture_args = args.clone();
    let writer_handle = std::thread::Builder::new()
        .name("capture-writer".into())
        .spawn(move || writer::run(capture_args, finished_tx))
        .context("spawning capture thread")?;

    // Wait for Ctrl+C, then ask the writer thread to wind down.
    tokio::signal::ctrl_c().await.ok();
    info!("received ctrl-c, shutting down");
    writer::request_shutdown();

    if let Err(e) = writer_handle.join().expect("capture thread panicked") {
        error!("capture/writer error: {e:#}");
    }
    // finished_tx is dropped inside writer::run, which closes the channel
    // and lets the uploader drain remaining work and exit.
    if let Err(e) = upload_handle.await? {
        error!("uploader error: {e:#}");
    }

    info!("clean shutdown complete");
    Ok(())
}

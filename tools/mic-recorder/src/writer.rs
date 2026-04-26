use anyhow::{Context, Result};
use std::io::BufWriter;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc as std_mpsc;
use std::time::{Duration, Instant};
use time::OffsetDateTime;
use tokio::sync::mpsc as tokio_mpsc;
use tracing::{debug, info, warn};

use crate::capture::{self, AudioChunk};
use crate::Args;

static SHUTDOWN: AtomicBool = AtomicBool::new(false);

pub fn request_shutdown() {
    SHUTDOWN.store(true, Ordering::SeqCst);
}

/// Metadata describing a finalized WAV file, handed off to the uploader.
pub struct FinishedSegment {
    pub local_path: PathBuf,
    pub started_at: OffsetDateTime,
    pub duration_seconds: u64,
    pub sample_rate: u32,
    pub channels: u16,
    pub size_bytes: u64,
}

type WavWriter = hound::WavWriter<BufWriter<std::fs::File>>;

struct ActiveSegment {
    writer: WavWriter,
    local_path: PathBuf,
    started_at: OffsetDateTime,
    started_instant: Instant,
}

/// Synchronous capture+writer loop. Owns the cpal Stream for its whole life.
pub fn run(args: Args, finished_tx: tokio_mpsc::Sender<FinishedSegment>) -> Result<()> {
    let (tx, rx) = std_mpsc::channel::<AudioChunk>();
    let opened = capture::open_stream(args.device.as_deref(), tx)?;
    // Hold the stream alive for the duration of this function.
    let _stream_guard = opened.stream;

    let spec = hound::WavSpec {
        channels: opened.channels,
        sample_rate: opened.sample_rate,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };
    let rotation = Duration::from_secs(args.rotation_seconds);
    let mut active = open_segment(&args.output_dir, spec)?;

    loop {
        if SHUTDOWN.load(Ordering::SeqCst) {
            finalize_and_send(active, &finished_tx, opened.sample_rate, opened.channels)?;
            break;
        }

        // Pull samples with a short timeout so rotation/shutdown stay responsive
        // even if the device pauses delivering data.
        match rx.recv_timeout(Duration::from_millis(200)) {
            Ok(chunk) => {
                for s in chunk.samples {
                    if let Err(e) = active.writer.write_sample(s) {
                        warn!("wav write_sample failed: {e}");
                        break;
                    }
                }
            }
            Err(std_mpsc::RecvTimeoutError::Timeout) => {}
            Err(std_mpsc::RecvTimeoutError::Disconnected) => {
                warn!("audio sample channel disconnected");
                finalize_and_send(active, &finished_tx, opened.sample_rate, opened.channels)?;
                break;
            }
        }

        if active.started_instant.elapsed() >= rotation {
            let next = open_segment(&args.output_dir, spec)?;
            let just_finished = std::mem::replace(&mut active, next);
            finalize_and_send(just_finished, &finished_tx, opened.sample_rate, opened.channels)?;
        }
    }

    drop(finished_tx);
    info!("writer loop exited");
    Ok(())
}

fn open_segment(dir: &std::path::Path, spec: hound::WavSpec) -> Result<ActiveSegment> {
    let started_at = OffsetDateTime::now_utc();
    let filename = format!(
        "{:04}-{:02}-{:02}T{:02}-{:02}-{:02}Z.wav",
        started_at.year(),
        u8::from(started_at.month()),
        started_at.day(),
        started_at.hour(),
        started_at.minute(),
        started_at.second(),
    );
    let local_path = dir.join(&filename);
    let writer = hound::WavWriter::create(&local_path, spec)
        .with_context(|| format!("creating wav file at {local_path:?}"))?;
    debug!("opened new segment: {local_path:?}");
    Ok(ActiveSegment {
        writer,
        local_path,
        started_at,
        started_instant: Instant::now(),
    })
}

fn finalize_and_send(
    seg: ActiveSegment,
    tx: &tokio_mpsc::Sender<FinishedSegment>,
    sample_rate: u32,
    channels: u16,
) -> Result<()> {
    let duration_seconds = seg.started_instant.elapsed().as_secs();
    let local_path = seg.local_path.clone();
    seg.writer
        .finalize()
        .with_context(|| format!("finalizing wav {local_path:?}"))?;
    let size_bytes = std::fs::metadata(&local_path).map(|m| m.len()).unwrap_or(0);
    let finished = FinishedSegment {
        local_path,
        started_at: seg.started_at,
        duration_seconds,
        sample_rate,
        channels,
        size_bytes,
    };
    info!(
        "finalized segment {:?} ({} s, {} bytes)",
        finished.local_path, finished.duration_seconds, finished.size_bytes
    );
    // blocking_send is fine here; we're on a std::thread, not a tokio task.
    tx.blocking_send(finished)
        .map_err(|e| anyhow::anyhow!("uploader channel closed: {e}"))?;
    Ok(())
}

use anyhow::{anyhow, Context, Result};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{Device, SampleFormat, Stream, StreamConfig};
use std::sync::mpsc::Sender;
use tracing::{info, warn};

pub struct AudioChunk {
    pub samples: Vec<i16>,
}

pub struct OpenedStream {
    pub stream: Stream,
    pub sample_rate: u32,
    pub channels: u16,
}

pub fn list_devices() -> Result<()> {
    let host = cpal::default_host();
    let default_name = host
        .default_input_device()
        .and_then(|d| d.name().ok())
        .unwrap_or_else(|| "<none>".into());
    println!("default input: {default_name}");
    println!("all input devices:");
    for device in host.input_devices()? {
        let name = device.name().unwrap_or_else(|_| "<unknown>".into());
        let cfg = device
            .default_input_config()
            .map(|c| format!("{} ch, {} Hz, {:?}", c.channels(), c.sample_rate().0, c.sample_format()))
            .unwrap_or_else(|e| format!("(no default config: {e})"));
        println!("  - {name}  [{cfg}]");
    }
    Ok(())
}

fn select_device(name_substr: Option<&str>) -> Result<Device> {
    let host = cpal::default_host();
    if let Some(needle) = name_substr {
        let needle_lc = needle.to_lowercase();
        for device in host.input_devices()? {
            if let Ok(n) = device.name() {
                if n.to_lowercase().contains(&needle_lc) {
                    info!("selected input device: {n}");
                    return Ok(device);
                }
            }
        }
        return Err(anyhow!("no input device matched substring {needle:?}"));
    }
    let device = host
        .default_input_device()
        .ok_or_else(|| anyhow!("no default input device"))?;
    info!("selected default input device: {}", device.name().unwrap_or_default());
    Ok(device)
}

pub fn open_stream(name_substr: Option<&str>, tx: Sender<AudioChunk>) -> Result<OpenedStream> {
    let device = select_device(name_substr)?;
    let supported = device.default_input_config().context("default_input_config")?;
    let sample_format = supported.sample_format();
    let channels = supported.channels();
    let sample_rate = supported.sample_rate().0;
    let config: StreamConfig = supported.into();
    info!(
        "opening input stream: {} Hz, {} ch, {:?}",
        sample_rate, channels, sample_format
    );

    let err_fn = |err| warn!("audio stream error: {err}");

    // Build a stream variant for the device's native sample format,
    // converting to i16 in the callback. We could resample/down-mix here
    // later if needed; for v1 we trust the device defaults.
    let stream = match sample_format {
        SampleFormat::I16 => device.build_input_stream(
            &config,
            move |data: &[i16], _: &_| {
                let _ = tx.send(AudioChunk { samples: data.to_vec() });
            },
            err_fn,
            None,
        ),
        SampleFormat::U16 => device.build_input_stream(
            &config,
            move |data: &[u16], _: &_| {
                let samples = data.iter().map(|&s| (s as i32 - 32768) as i16).collect();
                let _ = tx.send(AudioChunk { samples });
            },
            err_fn,
            None,
        ),
        SampleFormat::F32 => device.build_input_stream(
            &config,
            move |data: &[f32], _: &_| {
                let samples = data
                    .iter()
                    .map(|&s| (s.clamp(-1.0, 1.0) * i16::MAX as f32) as i16)
                    .collect();
                let _ = tx.send(AudioChunk { samples });
            },
            err_fn,
            None,
        ),
        other => return Err(anyhow!("unsupported sample format from device: {other:?}")),
    }
    .context("build_input_stream")?;

    stream.play().context("stream.play")?;
    Ok(OpenedStream { stream, sample_rate, channels })
}

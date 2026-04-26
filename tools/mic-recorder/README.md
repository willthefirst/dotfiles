# mic-recorder

Continuous USB microphone recorder. Captures audio in 1-minute chunks, writes
timestamped WAV files, and (optionally) uploads them to a Cloudflare R2 bucket
along with a JSON manifest so downstream clients can discover new segments.

## Why this shape

- **One-minute rotation** so a crash loses at most ~60s of audio.
- **R2 + CDN** for distribution: the recording machine just uploads, listeners
  fetch from Cloudflare. Egress is free.
- **WAV today, FLAC later.** WAV keeps v1 trivially correct; the encoder lives
  in one module and can be swapped for a streaming FLAC encoder without
  touching the capture, rotation, or upload code paths.

## Build

```bash
cd tools/mic-recorder
cargo build --release
# binary: target/release/mic-recorder
```

System deps: ALSA dev headers on Linux (`libasound2-dev` on Debian/Ubuntu).

## Usage

```bash
# List available input devices, then exit.
mic-recorder --list-devices

# Smoke-test capture without R2 (writes WAV files into ./recordings/).
mic-recorder --dry-run

# Production: writes locally AND uploads each finished segment to R2.
R2_ACCOUNT_ID=...           \
R2_ACCESS_KEY_ID=...        \
R2_SECRET_ACCESS_KEY=...    \
R2_BUCKET=my-audio          \
R2_PUBLIC_BASE_URL=https://pub-xxxx.r2.dev  \
mic-recorder
```

### Flags

| Flag | Default | Notes |
|---|---|---|
| `--device <name>` | system default input | substring match against `--list-devices` output |
| `--rotation-seconds <n>` | `60` | how often to close one file and start the next |
| `--output-dir <path>` | `./recordings` | where local WAVs are buffered before upload |
| `--keep-local` | off | by default, uploaded files are deleted locally |
| `--dry-run` | off | skip R2 entirely; just write local files |
| `--key-prefix <s>` | `audio` | R2 key prefix; final keys look like `audio/2026/04/26/2026-04-26T14-30-00Z.wav` |

## R2 setup

1. Cloudflare dashboard → R2 → **Create bucket**.
2. R2 → **Manage R2 API Tokens** → create a token with **Object Read & Write** scoped to that bucket.
3. Note the Account ID, Access Key ID, Secret Access Key.
4. Either enable the bucket's public `r2.dev` URL, or attach a custom domain.
   Set `R2_PUBLIC_BASE_URL` to whichever you chose (no trailing slash).

## Manifest layout (in the bucket)

- `index.json` — rolling window, last 24h, rewritten after every upload.
- `archive/YYYY-MM-DD.json` — append-only per-day list.

Both have the same shape:

```json
{
  "updated_at": "2026-04-26T14:31:02Z",
  "segments": [
    {
      "key": "audio/2026/04/26/2026-04-26T14-30-00Z.wav",
      "url": "https://pub-xxxx.r2.dev/audio/2026/04/26/2026-04-26T14-30-00Z.wav",
      "started_at": "2026-04-26T14:30:00Z",
      "duration_seconds": 60,
      "size_bytes": 5764844,
      "sample_rate": 48000,
      "channels": 1
    }
  ]
}
```

## Run as a service

See `mic-recorder.service`. Install:

```bash
sudo cp mic-recorder.service /etc/systemd/system/
sudo systemctl edit mic-recorder      # add R2_* env vars in the override
sudo systemctl enable --now mic-recorder
journalctl -u mic-recorder -f
```

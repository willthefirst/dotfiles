use serde::{Deserialize, Serialize};
use time::format_description::well_known::Rfc3339;
use time::OffsetDateTime;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Segment {
    pub key: String,
    pub url: String,
    pub started_at: String,
    pub duration_seconds: u64,
    pub size_bytes: u64,
    pub sample_rate: u32,
    pub channels: u16,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Manifest {
    pub updated_at: String,
    pub segments: Vec<Segment>,
}

impl Manifest {
    pub fn touch(&mut self) {
        self.updated_at = OffsetDateTime::now_utc()
            .format(&Rfc3339)
            .unwrap_or_default();
    }

    /// Append a segment and trim the in-memory list to the most recent `keep` entries.
    pub fn push_trimmed(&mut self, seg: Segment, keep: usize) {
        self.segments.push(seg);
        if self.segments.len() > keep {
            let drop_n = self.segments.len() - keep;
            self.segments.drain(..drop_n);
        }
        self.touch();
    }

    pub fn append(&mut self, seg: Segment) {
        self.segments.push(seg);
        self.touch();
    }
}

pub fn day_archive_key(date: time::Date) -> String {
    format!(
        "archive/{:04}-{:02}-{:02}.json",
        date.year(),
        u8::from(date.month()),
        date.day()
    )
}

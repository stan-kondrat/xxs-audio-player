# XXS Audio Player — native macOS audio player

[![Build](https://github.com/stan-kondrat/xxs-audo-player/actions/workflows/build.yml/badge.svg)](https://github.com/stan-kondrat/xxs-audo-player/actions/workflows/build.yml)
[![Release](https://github.com/stan-kondrat/xxs-audo-player/actions/workflows/release.yml/badge.svg)](https://github.com/stan-kondrat/xxs-audo-player/actions/workflows/release.yml)

Zero dependencies, privacy-first, offline-only. Pure Cocoa + AVFoundation.

---

## Features

- **Playlist** — drag & drop audio files, or File → Open (⌘O)
- **Play / Pause** — Space key or circular play button
- **Next / Previous** — skip forward/backward in playlist
- **Seek bar** — drag or use ←/→ arrows (5s steps)
- **Volume slider** — drag or use ↑/↓ arrows
- **Shuffle** — Fisher-Yates randomisation
- **Repeat** — three modes: off / repeat-all / repeat-one
- **ID3 tag parsing** — automatic encoding detection (UTF-8, UTF-16, Windows-1251, ISO-8859-1) with mojibake recovery
- **System media keys** — play/pause/next/prev/seek via keyboard media buttons (F7/F8/F9 or Touch Bar)
- **Glass UI** — dark vibrancy panels with hover glow, thin modern sliders, and adaptive transparency
- **Zero dependencies** — pure Cocoa + AVFoundation + MediaPlayer, no third-party libraries

## Build

```bash
make
```

Or build for a specific architecture:

```bash
make build-arm64     # Apple Silicon (macOS 11.0+)
make build-x86_64    # Intel (macOS 10.13+)
```

## Run

```bash
make run
```

Or directly:

```bash
./build/MusicPlayer.app/Contents/MacOS/MusicPlayer
```

## Usage

| Action | Method |
|--------|--------|
| Add files | Drag & drop onto window, or File → Open (⌘O) |
| Play / Pause | Space, or click ▶/⏸ button |
| Next track | ⌘→, or click ⏭ |
| Previous track | ⌘←, or click ⏮ |
| Seek | ← / → (5s), or drag seek slider |
| Volume | ↑ / ↓ (5%), or drag volume slider |
| Shuffle | S, or click 🔀 |
| Repeat | R, or click 🔁 |
| Remove track | Select in playlist, press Delete |
| Media keys | F7 (prev), F8 (play/pause), F9 (next) |

## Supported formats

`.mp3`, `.m4a`, `.wav`, `.aiff`, `.aac`, `.flac`, `.alac`, `.ogg`

## Architecture

| Layer | Framework | Role |
|-------|-----------|------|
| **Window** | Cocoa (AppKit) | `NSWindow` with transparent title bar, vibrancy background |
| **UI** | Cocoa (AppKit) | `NSTableView` playlist, `NSSlider` seek/volume, custom `GlassButton` |
| **Playback** | AVFoundation | `AVAudioPlayer` with progress timer |
| **Media keys** | MediaPlayer | `MPRemoteCommandCenter` for F7/F8/F9 and Touch Bar |
| **Metadata** | Direct ID3v1/v2 parsing | C file-level tag reading with automatic encoding detection and mojibake recovery |

### Files

| File | Purpose |
|------|---------|
| [`main.m`](main.m) | App delegate, UI layout, play controls, playlist management |
| [`ID3Metadata.h`](ID3Metadata.h) / [`ID3Metadata.m`](ID3Metadata.m) | ID3 tag parser with encoding detection (UTF-8, UTF-16, Windows-1251, ISO-8859-1) |

### Design

- **8px grid** — all layout spacing uses multiples of 8 (padding, gaps, button sizes, row heights)
- **Style constants** — every visual dimension lives at the top of `main.m` as `static const` or `#define`
- **Dark glass** — `NSVisualEffectView` panels with `NSVisualEffectMaterialDark` and `NSVisualEffectBlendingModeBehindWindow`
- **Custom controls** — `GlassButton` (pill/circular with hover glow), `GlassSliderCell` (thin bar with oversized knob), `CenteredTextFieldCell` (vertically centered table text)

## License

See [LICENSE.txt](LICENSE.txt).

# macOS Screen Recorder

A powerful, feature-rich command-line screen recorder for macOS built with Swift and ScreenCaptureKit.

## Features

- **High-Quality Recording** - Record up to 4K resolution at 60fps
- **Multiple Codecs** - H.264 and HEVC (H.265) support
- **Audio Capture** - System audio and microphone recording
- **Click Highlighting** - Visual feedback for mouse clicks (left/right/double-click)
- **Keystroke Overlay** - Display keyboard input on screen
- **Webcam PIP** - Picture-in-picture webcam overlay
- **Window Recording** - Record specific application windows
- **Watermark Support** - Add text watermarks to recordings
- **Auto-Save Settings** - Settings persist between sessions
- **Beautiful CLI Menu** - Interactive terminal interface

## Requirements

- macOS 13.0 (Ventura) or later
- Swift 5.7+

## Installation

### Build from Source

```bash
cd ScreenRecorderCLI
swift build -c release
```

The executable will be at `.build/release/screenrecord`

### Use the App Bundle

Double-click `ScreenRecorder.app` to launch the recorder in Terminal.

## Usage

### Interactive Mode
```bash
./screenrecord
```

### Command Line Options
```bash
# Record for 30 seconds
./screenrecord -t 30

# Record with microphone and click highlighting
./screenrecord --mic --clicks

# Record specific display
./screenrecord -d 1

# Show keystroke overlay
./screenrecord --keys

# Enable webcam PIP
./screenrecord --webcam

# List available displays and windows
./screenrecord --list
```

## Quality Presets

| Quality | Bitrate | Size/minute | Size/hour |
|---------|---------|-------------|-----------|
| Low | 5 Mbps | ~37 MB | ~2.2 GB |
| Optimized | 8 Mbps | ~60 MB | ~3.6 GB |
| Medium | 10 Mbps | ~75 MB | ~4.5 GB |
| High | 15 Mbps | ~112 MB | ~6.7 GB |
| Ultra | 25 Mbps | ~187 MB | ~11.2 GB |

**Tip:** Use HEVC codec + Optimized quality for best quality/size ratio.

## Permissions Required

1. **Screen Recording** - System Settings → Privacy & Security → Screen Recording
2. **Microphone** (optional) - System Settings → Privacy & Security → Microphone
3. **Accessibility** (for click highlighting) - System Settings → Privacy & Security → Accessibility

## Menu Options

```
[1] Start Recording
[2] Recording Settings (Resolution, FPS, Codec, Quality)
[3] Audio Settings (System Audio, Microphone)
[4] Mouse Settings (Click Highlighting, Colors)
[5] Capture Target (Display, Window)
[6] Overlays (Keystrokes, Webcam, Watermark)
[7] Output Settings (Format, Directory, Auto-stop)
[8] Presets (Save/Load configurations)
[Q] Quit
```

## Project Structure

```
├── ScreenRecorderCLI/     # Main CLI application source
│   ├── Sources/
│   │   └── main.swift     # All source code
│   └── Package.swift      # Swift package manifest
├── ScreenRecorder.app/    # macOS app bundle (double-clickable)
└── README.md
```

## License

MIT License

## Author

Built with Swift and ScreenCaptureKit for macOS.

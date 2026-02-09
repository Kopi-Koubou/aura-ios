# Aura Demo Video Recording Guide

Quick guide for recording a 60-90 second demo video for hackathon submissions.

## Quick Start

```bash
cd /Users/devl/clawd/Aura
./record-demo.sh
```

This creates `~/Desktop/DemoVideos/aura-demo.mp4` (75 seconds by default).

## Prerequisites

- macOS with Xcode installed
- iOS Simulator (iPhone 15/16 Pro recommended for best visuals)
- Aura app built in Debug mode

## Recording Options

### Environment Variables

```bash
# Use specific device
export AURA_DEVICE_ID="YOUR-SIMULATOR-UUID"

# Custom duration (seconds)
export AURA_DURATION=60

# Skip build step
export AURA_SKIP_BUILD=1

# Don't convert to MP4 (keep .mov)
export AURA_CONVERT_MP4=0

# Don't reset app state
export AURA_RESET_STATE=0
```

### Examples

```bash
# 90-second demo with custom name
./record-demo.sh my-hackathon-demo

# Quick 60-second recording
AURA_DURATION=60 ./record-demo.sh quick-demo

# Recording without rebuilding
AURA_SKIP_BUILD=1 ./record-demo.sh
```

## Manual Recording (Alternative)

If the script doesn't work, record manually:

```bash
# 1. Boot simulator
xcrun simctl boot "iPhone 16 Pro"

# 2. Start recording
xcrun simctl io booted recordVideo ~/Desktop/demo.mov &

# 3. Launch app
xcrun simctl launch booted com.kato.Cosmos

# 4. Stop recording (Ctrl+C the recording process)
kill -INT %1

# 5. Convert to MP4
ffmpeg -i ~/Desktop/demo.mov -c:v libx264 -pix_fmt yuv420p ~/Desktop/demo.mp4
```

## Demo Flow (75 Seconds)

The recommended flow for hackathon submissions:

| Time | Screen | Action |
|------|--------|--------|
| 0-3s | Welcome | Show logo, tagline, features |
| 3-6s | Name Input | Type "Alex", tap Continue |
| 6-9s | Birthdate | Show zodiac detection |
| 9-12s | MBTI Intro | Brief intro screen |
| 12-35s | MBTI Test | Answer 8 questions rapidly |
| 35-45s | MBTI Result | Show personality type |
| 45-60s | Daily Reading | Scroll through cosmic energy |
| 60-70s | Weekly Outlook | Show week view |
| 70-75s | Profile | End on user profile |

## Tips for Great Demo Videos

1. **Use iPhone 16 Pro** - Best resolution (1179×2556)
2. **Enable "Show Device Bezels"** in Simulator for polished look
3. **Keep it under 90 seconds** - Hackathon judges are busy
4. **Show the "aha" moment** - The MBTI result or daily reading insight
5. **Smooth transitions** - Don't rush, let each screen breathe 1-2 seconds
6. **No personal data** - Use fake name (Alex) and generic birthdate

## Integrating DemoRecorder.swift

To use the automated navigation:

1. Copy `DemoRecorder.swift` to your project
2. Add to your `CosmosApp.swift`:

```swift
@main
struct CosmosApp: App {
    init() {
        #if DEBUG
        // Check for demo mode launch argument
        if CommandLine.arguments.contains("--demo-mode") {
            DemoMode.enable(autoNavigate: true, speed: 0.5)
        }
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .overlay {
                    #if DEBUG
                    if DemoMode.isEnabled {
                        DemoControlOverlay()
                    }
                    #endif
                }
        }
    }
}
```

3. Launch with demo mode:
```bash
xcrun simctl launch booted com.kato.Cosmos --demo-mode
```

## Post-Processing

### Trim Video (if needed)

```bash
# Using ffmpeg - extract 60 seconds starting at 5s
ffmpeg -i input.mp4 -ss 5 -t 60 -c copy output.mp4
```

### Compress for Web

```bash
# Smaller file size for GitHub/README
ffmpeg -i input.mp4 -c:v libx264 -crf 28 -preset slow -c:a aac -b:a 128k output-small.mp4
```

### Add to GitHub Repo

```bash
# Large videos: Use Git LFS
git lfs track "*.mp4"
git add demo-video.mp4

# Small videos (<25MB): Direct commit
git add demo-video.mp4
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "No simulator found" | Start Simulator.app manually first |
| "App not installed" | Build in Xcode first (Cmd+B) |
| Video is black | Make sure simulator is booted and visible |
| Recording stops early | Check disk space; use shorter duration |
| MP4 conversion fails | Install ffmpeg: `brew install ffmpeg` |

## Upload Destinations

- **GitHub**: Direct embed in README (drag-drop or Git LFS)
- **YouTube**: Unlisted video, embed link
- **Loom**: Quick shareable link
- **Google Drive**: Shareable link for judges

---

**Hackathon Checklist:**
- [ ] Video is 60-90 seconds
- [ ] Shows core features (MBTI + Horoscope)
- [ ] Clean, no crashes or errors
- [ ] MP4 format (universal compatibility)
- [ ] Under 50MB for easy sharing

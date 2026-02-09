#!/bin/bash

# Aura iOS Demo Video Recorder
# Simple, reliable recording for hackathon submissions
# Usage: ./record-demo.sh [output_name]

set -e

# Configuration
DEVICE_ID="${AURA_DEVICE_ID:-}"  # Set env var or auto-detect
OUTPUT_NAME="${1:-aura-demo}"
OUTPUT_DIR="${HOME}/Desktop/DemoVideos"
DURATION="${AURA_DURATION:-75}"  # Default 75 seconds (60-90 range)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Auto-detect iPhone simulator if not specified
if [ -z "$DEVICE_ID" ]; then
    log_info "Auto-detecting iOS Simulator..."
    DEVICE_ID=$(xcrun simctl list devices available | grep -E "iPhone.*(15|16|Pro)" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')
    
    if [ -z "$DEVICE_ID" ]; then
        # Fallback to any iPhone
        DEVICE_ID=$(xcrun simctl list devices available | grep "iPhone" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')
    fi
fi

if [ -z "$DEVICE_ID" ]; then
    log_error "No iOS Simulator found. Please start a simulator or set AURA_DEVICE_ID"
    exit 1
fi

log_info "Using device: $DEVICE_ID"

# Check if simulator is booted
BOOT_STATUS=$(xcrun simctl list devices | grep "$DEVICE_ID" | grep -o "Booted" || echo "Shutdown")

if [ "$BOOT_STATUS" != "Booted" ]; then
    log_info "Booting simulator..."
    xcrun simctl boot "$DEVICE_ID"
    sleep 3
fi

# Open Simulator.app if not running
if ! pgrep -q "Simulator"; then
    log_info "Opening Simulator.app"
    open -a Simulator
    sleep 2
fi

# Build the app first (optional, skip if already built)
if [ "${AURA_SKIP_BUILD:-}" != "1" ]; then
    log_info "Building Aura app..."
    cd "$(dirname "$0")"
    
    if [ -f "Aura.xcodeproj/project.pbxproj" ] || [ -f "Cosmos.xcodeproj/project.pbxproj" ]; then
        xcodebuild -scheme Cosmos -destination "platform=iOS Simulator,id=$DEVICE_ID" -configuration Debug build | tail -20
    else
        log_warn "No Xcode project found in current directory. Skipping build."
    fi
fi

# Install and launch app
log_info "Installing app on simulator..."
xcrun simctl install "$DEVICE_ID" "${AURA_APP_PATH:-$(find ~/Library/Developer/Xcode/DerivedData -name "Cosmos.app" -type d 2>/dev/null | head -1)}" 2>/dev/null || log_warn "App may already be installed"

# Reset app state for clean demo (optional)
if [ "${AURA_RESET_STATE:-1}" == "1" ]; then
    log_info "Resetting app state for clean demo..."
    xcrun simctl terminate "$DEVICE_ID" com.kato.Cosmos 2>/dev/null || true
    # Clear SwiftData/container data
    xcrun simctl spawn "$DEVICE_ID" rm -rf "${HOME}/Library/Developer/CoreSimulator/Devices/${DEVICE_ID}/data/Containers/Data/Application"/*/Library/Application\ Support/ 2>/dev/null || true
fi

# Start recording
OUTPUT_PATH="$OUTPUT_DIR/${OUTPUT_NAME}.mov"
log_info "Starting recording (${DURATION}s)..."
log_info "Output: $OUTPUT_PATH"

# Start recording in background
xcrun simctl io "$DEVICE_ID" recordVideo "$OUTPUT_PATH" &
RECORD_PID=$!

# Launch app
sleep 1
log_info "Launching Aura app..."
xcrun simctl launch "$DEVICE_ID" com.kato.Cosmos

# Record for specified duration
log_info "Recording demo... Press Ctrl+C to stop early"
sleep "$DURATION"

# Stop recording
log_info "Stopping recording..."
kill -INT $RECORD_PID 2>/dev/null || true
wait $RECORD_PID 2>/dev/null || true

# Convert to MP4 if requested
if [ "${AURA_CONVERT_MP4:-1}" == "1" ]; then
    MP4_PATH="$OUTPUT_DIR/${OUTPUT_NAME}.mp4"
    log_info "Converting to MP4..."
    
    # Use ffmpeg if available, otherwise use avconvert
    if command -v ffmpeg &> /dev/null; then
        ffmpeg -i "$OUTPUT_PATH" -c:v libx264 -preset fast -crf 23 -pix_fmt yuv420p -movflags +faststart -y "$MP4_PATH" 2>/dev/null
    else
        avconvert --preset PresetAppleM4V1080pHD --source "$OUTPUT_PATH" --output "$MP4_PATH" 2>/dev/null || \
        xcrun simctl io "$DEVICE_ID" screenshot "${OUTPUT_PATH%.mov}.png" 2>/dev/null
    fi
    
    # Remove original .mov if conversion successful
    if [ -f "$MP4_PATH" ]; then
        rm "$OUTPUT_PATH"
        OUTPUT_PATH="$MP4_PATH"
        log_info "✓ MP4 saved: $OUTPUT_PATH"
    else
        log_warn "MP4 conversion failed, keeping .mov file"
        log_info "✓ Video saved: $OUTPUT_PATH"
    fi
else
    log_info "✓ Video saved: $OUTPUT_PATH"
fi

# Get file size
FILE_SIZE=$(du -h "$OUTPUT_PATH" | cut -f1)
log_info "File size: $FILE_SIZE"

# Open containing folder
open "$OUTPUT_DIR"

log_info "Demo recording complete!"
echo ""
echo "Next steps:"
echo "  - Review the video at: $OUTPUT_PATH"
echo "  - Trim to 60-90 seconds if needed"
echo "  - Upload to GitHub, YouTube, or your hackathon submission"

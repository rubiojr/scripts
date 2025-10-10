#!/usr/bin/env bash
#
# video2gif.sh – Convert a video to an animated GIF (full length)
#
# Usage:
#   ./video2gif.sh INPUT_VIDEO [WIDTH] [FPS] [MAX_COLORS]
#
#   INPUT_VIDEO   Path to the source video (required)
#   WIDTH         Desired output width in pixels (default: 640)
#   FPS           Frames‑per‑second for the GIF (default: 15)
#   MAX_COLORS    Maximum colours after gifsicle optimisation (default: 128)
#
# Example:
#   ./video2gif.sh mymovie.mp4 480 12 96
#

set -euo pipefail

# ---------- Argument handling ----------
if [[ $# -lt 1 ]]; then
    echo "Error: No input video supplied."
    echo "Usage: $0 INPUT_VIDEO [WIDTH] [FPS] [MAX_COLORS]"
    exit 1
fi

INPUT="${1}"
WIDTH="${2:-1024}"          # default width 640 px
FPS="${3:-15}"             # default 15 fps
MAX_COLORS="${4:-128}"     # default 128 colours after optimisation

# Validate input file
if [[ ! -f "$INPUT" ]]; then
    echo "Error: File '$INPUT' not found."
    exit 1
fi

# Derive output names
BASE="${INPUT%.*}"               # strip extension
PALETTE="${BASE}_palette.png"
GIF_TMP="${BASE}_raw.gif"
GIF_OUT="${BASE}.gif"

# ---------- Step 1 – generate an optimal palette ----------
ffmpeg -y -i "$INPUT" -vf "fps=${FPS},scale=${WIDTH}:-1:flags=lanczos,palettegen" "$PALETTE"

# ---------- Step 2 – create the GIF using the palette ----------
ffmpeg -y -i "$INPUT" -i "$PALETTE" -filter_complex \
"[0:v]fps=${FPS},scale=${WIDTH}:-1:flags=lanczos[x];[x][1:v]paletteuse" "$GIF_TMP"

# ---------- Step 3 – optimise/compress the GIF ----------
# Requires gifsicle – install via your package manager if missing
gifsicle -O3 --colors "$MAX_COLORS" "$GIF_TMP" -o "$GIF_OUT"

# Cleanup intermediate files
rm -f "$PALETTE" "$GIF_TMP"

echo "✅ GIF created: $GIF_OUT"

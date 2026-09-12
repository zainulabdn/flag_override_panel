#!/usr/bin/env bash
#
# Turns the frames written by `capture_test.dart` into the images shipped in
# `doc/`, then reports what each one costs in the published archive.
#
#     cd example
#     flutter test tool/capture_test.dart
#     ./tool/make_media.sh
#
# Requires ffmpeg (brew install ffmpeg).

set -euo pipefail

cd "$(dirname "$0")/../.."
DOC="doc"
FRAMES="$DOC/.frames"

if ! command -v ffmpeg >/dev/null; then
  echo "ffmpeg not found. brew install ffmpeg" >&2
  exit 1
fi

if [ ! -d "$FRAMES" ] || [ -z "$(ls -A "$FRAMES" 2>/dev/null)" ]; then
  echo "No frames in $FRAMES. Run: cd example && flutter test tool/capture_test.dart" >&2
  exit 1
fi

# Frames are captured one per 60ms of app time, so 16fps plays back at roughly
# real speed.
FPS=16
WIDTH=860
COLORS=128

echo "==> Building $DOC/demo.gif"
ffmpeg -y -loglevel error \
  -framerate "$FPS" -i "$FRAMES/f%04d.png" \
  -vf "fps=$FPS,scale=$WIDTH:-1:flags=lanczos,split[a][b];\
[a]palettegen=max_colors=$COLORS:stats_mode=diff[p];\
[b][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle" \
  -loop 0 "$DOC/demo.gif"

# The stills are captured at 2x for HiDPI, so they are heavy straight out of
# the rasteriser. Re-encode them losslessly — same pixels, smaller archive.
for png in "$DOC"/*.png; do
  [ -e "$png" ] || continue
  before=$(wc -c <"$png")
  ffmpeg -y -loglevel error -i "$png" -compression_level 100 -pred mixed "$png.tmp.png"
  after=$(wc -c <"$png.tmp.png")
  if [ "$after" -lt "$before" ]; then
    mv "$png.tmp.png" "$png"
  else
    rm -f "$png.tmp.png"
  fi
  echo "==> $(basename "$png"): $((before / 1024))K -> $((after / 1024))K"
done

echo
echo "==> Shipped media"
du -ch "$DOC"/*.png "$DOC"/demo.gif | tail -20

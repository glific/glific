#!/usr/bin/env bash
set -euo pipefail

FFMPEG_URL="https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2026-04-30-13-44/ffmpeg-N-124278-gcc3ca17127-linux64-gpl.tar.xz"
FFMPEG_SHA256="cd50a631135f90fecd0166c5134e32326825bc6bd11da4bf4ea24d5cb2f79f1f"
INSTALL_DIR="rel/overlays/vendor/ffmpeg"

echo "-----> Installing ffmpeg from BtbN static build (ffmpeg.org recommended source)"

mkdir -p "$INSTALL_DIR"

echo "       Downloading $FFMPEG_URL"
curl -L --silent --fail --retry 3 -o /tmp/ffmpeg.tar.xz "$FFMPEG_URL"

echo "       Verifying checksum"
echo "${FFMPEG_SHA256}  /tmp/ffmpeg.tar.xz" | sha256sum -c -

echo "       Extracting"
tar -xJf /tmp/ffmpeg.tar.xz -C /tmp --strip-components=1 --wildcards '*/bin/ffmpeg' '*/bin/ffprobe'
mv /tmp/bin/ffmpeg "$INSTALL_DIR/ffmpeg"
mv /tmp/bin/ffprobe "$INSTALL_DIR/ffprobe"
chmod +x "$INSTALL_DIR/ffmpeg" "$INSTALL_DIR/ffprobe"

rm -f /tmp/ffmpeg.tar.xz
rmdir /tmp/bin 2>/dev/null || true

echo "       ffmpeg installed to $INSTALL_DIR"

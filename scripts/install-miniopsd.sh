#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Building miniopsd..."
swift build -c release --product miniopsd

BIN="$ROOT/.build/release/miniopsd"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

echo "Installing to $INSTALL_DIR/miniopsd"
sudo mkdir -p "$INSTALL_DIR"
sudo cp "$BIN" "$INSTALL_DIR/miniopsd"
sudo chmod +x "$INSTALL_DIR/miniopsd"

echo "Done. Run: miniopsd --print-config"

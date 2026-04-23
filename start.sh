#!/usr/bin/env bash
# PortableAI — Zero Dependency Launcher (Linux / macOS)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo " ╔═══════════════════════════════════════════╗"
echo " ║      PortableAI  —  Zero Dependency       ║"
echo " ║      Plug-and-play Local LLM Server       ║"
echo " ╚═══════════════════════════════════════════╝"
echo ""

# ── Find model ───────────────────────────────────────────────────────────────
MODEL=$(find "$SCRIPT_DIR/models" -maxdepth 1 -name "*.gguf" -type f | sort | head -n1)
if [ -z "$MODEL" ]; then
    echo " [!] No .gguf model found in models/"
    echo "     Download one from https://huggingface.co"
    echo "     Recommended: any Q4_K_M quantization"
    exit 1
fi

# ── Pick binary ───────────────────────────────────────────────────────────────
OS=$(uname -s)
ARCH=$(uname -m)
case "$OS" in
    Linux*)
        BIN="$SCRIPT_DIR/bin/linux/llama-server-linux"
        ;;
    Darwin*)
        if [ "$ARCH" = "arm64" ]; then
            BIN="$SCRIPT_DIR/bin/mac/mac_arm64/llama-server-mac-arm"
        else
            BIN="$SCRIPT_DIR/bin/mac/mac_x64/llama-server-mac-x64"
        fi
        ;;
    *)
        echo " [!] Unsupported OS: $OS"
        exit 1
        ;;
esac

if [ ! -f "$BIN" ]; then
    echo " [!] Binary not found: $BIN"
    echo "     First run the install.sh"
    exit 1
fi

chmod +x "$BIN"

# ── Thread count ──────────────────────────────────────────────────────────────
if command -v nproc &>/dev/null; then
    THREADS=$(( $(nproc) - 1 ))
elif command -v sysctl &>/dev/null; then
    THREADS=$(( $(sysctl -n hw.ncpu) - 1 ))
else
    THREADS=3
fi
[ "$THREADS" -lt 1 ] && THREADS=1

echo " [+] Model  : $(basename "$MODEL")"
echo " [+] Threads: $THREADS"
echo " [+] UI     : http://127.0.0.1:8080"
echo " [+] LAN    : http://0.0.0.0:8080"
echo ""
echo " Press Ctrl+C to stop."
echo " ─────────────────────────────────────────────"

# Open browser
(sleep 3 && \
  (command -v xdg-open &>/dev/null && xdg-open "http://127.0.0.1:8080") || \
  (command -v open     &>/dev/null && open     "http://127.0.0.1:8080") \
) &

"$BIN" \
    -m "$MODEL" \
    -c 4096 \
    -t "$THREADS" \
    --port 8080 \
    --host 0.0.0.0 \
    --path "$SCRIPT_DIR/ui"

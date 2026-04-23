#!/usr/bin/env bash
# PortableAI — Launcher (Linux / macOS)
#
# Selects the correct binary for the current OS/arch, sets LD_LIBRARY_PATH
# so shared libs (.so / .dylib) next to the binary are found automatically,
# then starts the llama.cpp web server.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'

echo ""
echo -e "${CYAN} ╔═══════════════════════════════════════════╗${NC}"
echo -e "${CYAN} ║      PortableAI  —  Zero Dependency       ║${NC}"
echo -e "${CYAN} ║      Plug-and-play Local LLM Server       ║${NC}"
echo -e "${CYAN} ╚═══════════════════════════════════════════╝${NC}"
echo ""

# ── Collect all .gguf models ──────────────────────────────────────────────────
mapfile -t MODELS < <(find "$SCRIPT_DIR/models" -maxdepth 1 -name "*.gguf" -type f 2>/dev/null | sort)

if [ "${#MODELS[@]}" -eq 0 ]; then
    echo -e "${RED} [!] No .gguf model found in models/${NC}"
    echo "     Download one from https://huggingface.co"
    echo "     Recommended: any Q4_K_M quantization"
    exit 1
fi

# ── Model selection ───────────────────────────────────────────────────────────
if [ "${#MODELS[@]}" -eq 1 ]; then
    MODEL="${MODELS[0]}"
    echo -e " ${GREEN}[+] Using model :${NC} $(basename "$MODEL")"
else
    echo -e " ${BOLD} [?] Multiple models found — select one:${NC}"
    echo "     ─────────────────────────────────────────────"
    for i in "${!MODELS[@]}"; do
        SIZE=$(du -sh "${MODELS[$i]}" 2>/dev/null | cut -f1)
        printf "     ${BOLD}[%d]${NC} %-50s %s\n" "$((i+1))" "$(basename "${MODELS[$i]}")" "$SIZE"
    done
    echo ""
    while true; do
        read -rp " Enter number [1-${#MODELS[@]}]: " CHOICE
        if [[ "$CHOICE" =~ ^[0-9]+$ ]] \
            && [ "$CHOICE" -ge 1 ] \
            && [ "$CHOICE" -le "${#MODELS[@]}" ]; then
            MODEL="${MODELS[$((CHOICE-1))]}"
            break
        fi
        echo -e "${RED} [!] Invalid. Enter a number between 1 and ${#MODELS[@]}.${NC}"
    done
    echo ""
    echo -e " ${GREEN}[+] Selected :${NC} $(basename "$MODEL")"
fi

# ── Detect OS / Architecture and pick binary ──────────────────────────────────
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
    Linux*)
        case "$ARCH" in
            x86_64)
                BIN_DIR="$SCRIPT_DIR/bin/linux/linux_x64"
                BIN="$BIN_DIR/llama-server-linux-x64"
                ;;
            aarch64)
                BIN_DIR="$SCRIPT_DIR/bin/linux/linux_arm64"
                BIN="$BIN_DIR/llama-server-linux-arm"
                ;;
            *)
                echo -e "${RED} [!] Unsupported Linux architecture: $ARCH${NC}"
                exit 1 ;;
        esac
        ;;
    Darwin*)
        case "$ARCH" in
            arm64)
                BIN_DIR="$SCRIPT_DIR/bin/mac/mac_arm64"
                BIN="$BIN_DIR/llama-server-mac-arm"
                ;;
            x86_64)
                BIN_DIR="$SCRIPT_DIR/bin/mac/mac_x64"
                BIN="$BIN_DIR/llama-server-mac-x64"
                ;;
            *)
                echo -e "${RED} [!] Unsupported macOS architecture: $ARCH${NC}"
                exit 1 ;;
        esac
        ;;
    *)
        echo -e "${RED} [!] Unsupported OS: $OS${NC}"
        echo "     Windows users: run start.bat instead."
        exit 1 ;;
esac

if [ ! -f "$BIN" ]; then
    echo -e "${RED} [!] Binary not found: $BIN${NC}"
    echo "     Run ./install.sh first."
    exit 1
fi
chmod +x "$BIN"

# ── Set library search path so .so/.dylib files next to binary are found ──────
# llama-server links against libllama.so, libggml.so, libggml-cpu.so etc.
# install.sh copies all of them into BIN_DIR alongside the binary.
case "$OS" in
    Linux*)
        export LD_LIBRARY_PATH="$BIN_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        ;;
    Darwin*)
        export DYLD_LIBRARY_PATH="$BIN_DIR${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
        ;;
esac

# ── Thread count (all logical cores minus one) ────────────────────────────────
if command -v nproc &>/dev/null; then
    THREADS=$(( $(nproc) - 1 ))
elif command -v sysctl &>/dev/null; then
    THREADS=$(( $(sysctl -n hw.ncpu) - 1 ))
else
    THREADS=3
fi
[ "$THREADS" -lt 1 ] && THREADS=1

# ── Launch info ───────────────────────────────────────────────────────────────
echo ""
echo -e " ${GREEN}[+] OS       :${NC} $OS ($ARCH)"
echo -e " ${GREEN}[+] Threads  :${NC} $THREADS"
echo -e " ${GREEN}[+] Local UI :${NC} http://127.0.0.1:8080"
echo -e " ${GREEN}[+] LAN      :${NC} http://0.0.0.0:8080  (same Wi-Fi)"
echo ""
echo " Press Ctrl+C to stop the server."
echo " ─────────────────────────────────────────────"

# ── Open browser after 3 seconds ─────────────────────────────────────────────
(sleep 3 && \
    if command -v xdg-open &>/dev/null; then
        xdg-open "http://127.0.0.1:8080" &>/dev/null
    elif command -v open &>/dev/null; then
        open "http://127.0.0.1:8080"
    fi
) &>/dev/null &

# ── Start server ──────────────────────────────────────────────────────────────
exec "$BIN" \
    -m "$MODEL" \
    -c 4096 \
    -t "$THREADS" \
    --port 8080 \
    --host 0.0.0.0

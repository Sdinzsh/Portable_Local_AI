#!/usr/bin/env bash
# PortableAI — Auto Installer (Linux / macOS)
#
# The llama.cpp tar.gz archive is built as:
#   tar -C ./build/bin --transform "s,./,llama-bXXXX/," -czvf archive.tar.gz .
#
# So inside the archive every file lives under a versioned folder like:
#   llama-b8893/llama-server
#   llama-b8893/libllama.so
#   llama-b8893/libggml.so   (and other .so deps)
#   llama-b8893/llama-cli
#   ... etc.
#
# We must extract ALL of those files into the bin destination dir so that
# llama-server can find its shared libraries at runtime.
# Only llama-server itself gets renamed; everything else keeps its name.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

echo -e "${CYAN}"
echo " ╔═══════════════════════════════════════════╗"
echo " ║      PortableAI  —  Auto Installer        ║"
echo " ║      Downloads llama.cpp server binary    ║"
echo " ╚═══════════════════════════════════════════╝"
echo -e "${NC}"

# ── Dependency check ──────────────────────────────────────────────────────────
for cmd in curl tar; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${RED} [!] Required tool missing: $cmd${NC}"
        echo "     Manjaro/CachyOS : sudo pacman -S $cmd"
        echo "     Ubuntu/Debian   : sudo apt install $cmd"
        exit 1
    fi
done

# ── Detect OS / Architecture ──────────────────────────────────────────────────
OS="$(uname -s)"
ARCH="$(uname -m)"

echo -e " ${BOLD}[*] Detected OS   :${NC} $OS"
echo -e " ${BOLD}[*] Detected Arch :${NC} $ARCH"
echo ""

case "$OS" in
    Linux*)
        case "$ARCH" in
            x86_64)
                # Asset name pattern: llama-bXXXX-bin-ubuntu-x64.tar.gz
                ASSET_GREP="ubuntu-x64\.tar\.gz"
                BIN_DEST="$SCRIPT_DIR/bin/linux/linux_x64"
                BIN_FINAL="llama-server-linux-x64"
                ;;
            aarch64)
                # Asset name pattern: llama-bXXXX-bin-ubuntu-arm64.tar.gz
                ASSET_GREP="ubuntu-arm64\.tar\.gz"
                BIN_DEST="$SCRIPT_DIR/bin/linux/linux_arm64"
                BIN_FINAL="llama-server-linux-arm"
                ;;
            *)
                echo -e "${RED} [!] Unsupported Linux arch: $ARCH${NC}"
                exit 1 ;;
        esac
        ;;
    Darwin*)
        case "$ARCH" in
            arm64)
                ASSET_GREP="macos-arm64\.tar\.gz"
                BIN_DEST="$SCRIPT_DIR/bin/mac/mac_arm64"
                BIN_FINAL="llama-server-mac-arm"
                ;;
            x86_64)
                ASSET_GREP="macos-x64\.tar\.gz"
                BIN_DEST="$SCRIPT_DIR/bin/mac/mac_x64"
                BIN_FINAL="llama-server-mac-x64"
                ;;
            *)
                echo -e "${RED} [!] Unsupported macOS arch: $ARCH${NC}"
                exit 1 ;;
        esac
        ;;
    *)
        echo -e "${RED} [!] Unsupported OS: $OS${NC}"
        exit 1 ;;
esac

echo -e " ${GREEN}[✓] Install dir   :${NC} $BIN_DEST"
echo -e " ${GREEN}[✓] Server binary :${NC} $BIN_FINAL"
echo ""

# ── Fetch latest release JSON ─────────────────────────────────────────────────
echo -e " ${YELLOW}[*] Fetching latest llama.cpp release from GitHub API...${NC}"

RELEASE_JSON=$(curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/ggml-org/llama.cpp/releases/latest") || {
    echo -e "${RED} [!] Failed to reach GitHub API. Check your internet connection.${NC}"
    exit 1
}

RELEASE_TAG=$(echo "$RELEASE_JSON" \
    | grep '"tag_name"' | head -1 \
    | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')

if [ -z "$RELEASE_TAG" ]; then
    echo -e "${RED} [!] Could not parse release tag. GitHub may be rate-limiting.${NC}"
    echo " Response preview:"
    echo "$RELEASE_JSON" | head -c 300
    exit 1
fi
echo -e " ${GREEN}[✓] Latest release :${NC} $RELEASE_TAG"

# ── Pull all download URLs from the JSON ─────────────────────────────────────
ALL_URLS=$(echo "$RELEASE_JSON" \
    | grep '"browser_download_url"' \
    | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')

if [ -z "$ALL_URLS" ]; then
    echo -e "${RED} [!] No download URLs in API response (rate-limited?).${NC}"
    echo " Try again in a few minutes, or visit:"
    echo " https://github.com/ggml-org/llama.cpp/releases/latest"
    exit 1
fi

# ── Find our asset — skip GPU builds ─────────────────────────────────────────
echo -e " ${YELLOW}[*] Searching for matching CPU archive...${NC}"

ASSET_URL=$(echo "$ALL_URLS" \
    | grep -E "$ASSET_GREP" \
    | grep -iv "cuda\|vulkan\|rocm\|kompute\|sycl\|opencl\|mpi\|openvino\|openeuler\|kleidiai" \
    | head -1 || true)

if [ -z "$ASSET_URL" ]; then
    echo -e "${RED} [!] No matching asset found for pattern: $ASSET_GREP${NC}"
    echo ""
    echo " All non-GPU assets in $RELEASE_TAG:"
    echo "$ALL_URLS" \
        | grep -iv "cuda\|vulkan\|rocm\|kompute\|sycl\|opencl\|mpi\|openvino\|openeuler" \
        | while read -r url; do echo "     $(basename "$url")"; done
    echo ""
    echo " Manual fallback:"
    echo "   1. Download the tar.gz from https://github.com/ggml-org/llama.cpp/releases/latest"
    echo "   2. Extract ALL contents into: $BIN_DEST/"
    echo "   3. Rename llama-server → $BIN_DEST/$BIN_FINAL"
    exit 1
fi

ASSET_FILENAME="$(basename "$ASSET_URL")"
echo -e " ${GREEN}[✓] Asset found   :${NC} $ASSET_FILENAME"
echo ""

# ── Download ──────────────────────────────────────────────────────────────────
TMP_DIR="$(mktemp -d)"
trap 'echo ""; echo " [*] Cleaning up temp files..."; rm -rf "$TMP_DIR"' EXIT

echo -e " ${YELLOW}[*] Downloading...${NC}"
echo "     (Size is typically 10–80 MB for CPU builds)"
curl -L --progress-bar -o "$TMP_DIR/$ASSET_FILENAME" "$ASSET_URL" || {
    echo -e "${RED} [!] Download failed.${NC}"
    exit 1
}
echo ""

# ── Extract all files ─────────────────────────────────────────────────────────
# The tar.gz contains a versioned top-level folder: llama-b8893/
# We strip that prefix so all files land flat in EXTRACT_DIR.
echo -e " ${YELLOW}[*] Extracting all files from archive...${NC}"
EXTRACT_DIR="$TMP_DIR/extracted"
mkdir -p "$EXTRACT_DIR"

# --strip-components=1 removes the top-level versioned dir (llama-bXXXX/)
tar -xzf "$TMP_DIR/$ASSET_FILENAME" \
    -C "$EXTRACT_DIR" \
    --strip-components=1 || {
    echo -e "${RED} [!] Extraction failed.${NC}"
    # Try without --strip-components as fallback (some archives differ)
    echo " Retrying without --strip-components..."
    tar -xzf "$TMP_DIR/$ASSET_FILENAME" -C "$EXTRACT_DIR" || {
        echo -e "${RED} [!] Extraction failed completely.${NC}"
        exit 1
    }
    # If the top-level dir still exists, move its contents up
    INNER=$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)
    if [ -n "$INNER" ]; then
        mv "$INNER"/* "$EXTRACT_DIR/" 2>/dev/null || true
        rmdir "$INNER" 2>/dev/null || true
    fi
}

echo " Extracted files:"
ls -lh "$EXTRACT_DIR" | tail -n +2 | awk '{printf "     %-40s %s\n", $NF, $5}'
echo ""

# ── Install — copy ALL files to bin destination ───────────────────────────────
# llama-server links against libllama.so, libggml.so, libggml-cpu.so etc.
# All of them must live next to the binary (or in LD_LIBRARY_PATH).
# The simplest and most portable solution: put everything in BIN_DEST.
echo -e " ${YELLOW}[*] Installing all files to:${NC} $BIN_DEST"
mkdir -p "$BIN_DEST"

cp -r "$EXTRACT_DIR"/. "$BIN_DEST/"

# Fix permissions — make every file without an extension (binary) executable
find "$BIN_DEST" -maxdepth 1 -type f ! -name "*.*" -exec chmod +x {} \;
# Also make .so files readable
find "$BIN_DEST" -maxdepth 1 -type f -name "*.so*" -exec chmod 755 {} \; 2>/dev/null || true

echo -e " ${GREEN}[✓] All files installed.${NC}"

# ── Rename llama-server → our canonical name ──────────────────────────────────
if [ -f "$BIN_DEST/llama-server" ]; then
    cp "$BIN_DEST/llama-server" "$BIN_DEST/$BIN_FINAL"
    chmod +x "$BIN_DEST/$BIN_FINAL"
    echo -e " ${GREEN}[✓] Renamed        :${NC} llama-server → $BIN_FINAL"
else
    echo -e "${RED} [!] llama-server not found in extracted files!${NC}"
    echo " Contents of $BIN_DEST:"
    ls -lh "$BIN_DEST"
    exit 1
fi

# ── Web UI assets ─────────────────────────────────────────────────────────────
# llama.cpp no longer ships separate HTML files — the web UI is embedded
# in the llama-server binary itself. The --path flag just lets you override it.
mkdir -p "$SCRIPT_DIR/ui"
echo -e " ${YELLOW}[~] Note: llama.cpp now embeds the web UI in the binary.${NC}"
echo "     The ui/ folder is kept for compatibility but is not required."

# ── Ensure models directory exists ────────────────────────────────────────────
mkdir -p "$SCRIPT_DIR/models"

# ── Verify the binary runs ────────────────────────────────────────────────────
echo ""
echo -e " ${YELLOW}[*] Verifying binary...${NC}"
VERSION_OUT=$("$BIN_DEST/$BIN_FINAL" --version 2>&1 | head -2 || true)
if [ -n "$VERSION_OUT" ]; then
    echo -e " ${GREEN}[✓] Binary OK :${NC}"
    echo "$VERSION_OUT" | while read -r line; do echo "     $line"; done
else
    echo -e " ${YELLOW}[~] --version returned nothing (binary may still be fine).${NC}"
    echo "     If start.sh fails, check: ldd $BIN_DEST/$BIN_FINAL"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN} ╔═══════════════════════════════════════════╗${NC}"
echo -e "${GREEN} ║  ✅  Installation Complete!               ║${NC}"
echo -e "${GREEN} ╚═══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Release : ${CYAN}$RELEASE_TAG${NC}"
echo -e "  Files   → ${CYAN}$BIN_DEST/${NC}"
echo -e "  Server  → ${CYAN}$BIN_DEST/$BIN_FINAL${NC}"
echo -e "  Models  → ${CYAN}$SCRIPT_DIR/models/${NC}"
echo ""
echo " Next steps:"
echo "   1. Drop a .gguf model in:  models/"
echo "      Grab one from https://huggingface.co  (Q4_K_M recommended)"
echo "   2. Run:  ./start.sh"
echo ""

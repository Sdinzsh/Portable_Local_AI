#!/usr/bin/env bash
# PortableAI — Universal Installer (Linux / macOS)
#
# Downloads llama.cpp binaries for ALL platforms in one run:
#   Linux  x64   → bin/linux/linux_x64/
#   Linux  arm64 → bin/linux/linux_arm64/
#   macOS  arm64 → bin/mac/mac_arm64/
#   macOS  x64   → bin/mac/mac_x64/
#
# Windows binaries are handled by install.bat (run that on Windows).
#
# Archive layout inside tar.gz:
#   llama-bXXXX/llama-server   ← server binary
#   llama-bXXXX/libllama.so    ← required shared libs
#   llama-bXXXX/libggml.so
#   llama-bXXXX/libggml-cpu.so
#   ... etc.
# We strip the versioned top-level folder and copy EVERYTHING into BIN_DEST
# so that llama-server can find its .so dependencies at runtime.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

echo -e "${CYAN}"
echo " ╔═══════════════════════════════════════════╗"
echo " ║   PortableAI — Universal Installer        ║"
echo " ║   Downloads llama.cpp for all platforms   ║"
echo " ╚═══════════════════════════════════════════╝"
echo -e "${NC}"
echo -e " ${DIM}Windows users: run install.bat instead${NC}"
echo ""

# ── Dependency check ──────────────────────────────────────────────────────────
for cmd in curl tar; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${RED} [!] Required tool missing: $cmd${NC}"
        echo "     Manjaro/CachyOS : sudo pacman -S $cmd"
        echo "     Ubuntu/Debian   : sudo apt install $cmd"
        exit 1
    fi
done

# ── Fetch latest release JSON once ───────────────────────────────────────────
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
    echo "$RELEASE_JSON" | head -c 400
    exit 1
fi
echo -e " ${GREEN}[✓] Latest release :${NC} $RELEASE_TAG"
echo ""

# ── Extract all download URLs ─────────────────────────────────────────────────
ALL_URLS=$(echo "$RELEASE_JSON" \
    | grep '"browser_download_url"' \
    | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')

if [ -z "$ALL_URLS" ]; then
    echo -e "${RED} [!] No download URLs found (rate-limited?). Try again in a few minutes.${NC}"
    exit 1
fi

# ── Helper: download and install one platform ─────────────────────────────────
# Usage: install_platform  LABEL  ASSET_GREP  BIN_DEST  BIN_FINAL  ARCHIVE_TYPE
#   LABEL        — human label e.g. "Linux x64"
#   ASSET_GREP   — grep pattern to match asset filename
#   BIN_DEST     — destination directory
#   BIN_FINAL    — canonical server binary name after rename
#   ARCHIVE_TYPE — "tar.gz" or "zip"
install_platform() {
    local LABEL="$1"
    local ASSET_GREP="$2"
    local BIN_DEST="$3"
    local BIN_FINAL="$4"
    local ARCHIVE_TYPE="$5"

    echo -e "${CYAN} ┌─────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN} │  Installing: ${BOLD}$LABEL${NC}${CYAN}$(printf '%*s' $((45 - ${#LABEL})) '')│${NC}"
    echo -e "${CYAN} └─────────────────────────────────────────────┘${NC}"

    # Find matching asset URL (skip GPU builds)
    local ASSET_URL
    ASSET_URL=$(echo "$ALL_URLS" \
        | grep -E "$ASSET_GREP" \
        | grep -iv "cuda\|vulkan\|rocm\|kompute\|sycl\|opencl\|mpi\|openvino\|openeuler\|kleidiai" \
        | head -1 || true)

    if [ -z "$ASSET_URL" ]; then
        echo -e " ${YELLOW} [~] No asset found for $LABEL (skipping)${NC}"
        echo -e " ${DIM}     Pattern tried: $ASSET_GREP${NC}"
        echo ""
        return 0
    fi

    local ASSET_FILENAME
    ASSET_FILENAME="$(basename "$ASSET_URL")"
    echo -e "  ${GREEN}[✓] Asset    :${NC} $ASSET_FILENAME"
    echo -e "  ${GREEN}[✓] Dest dir :${NC} $BIN_DEST"

    # Temp workspace
    local TMP_DIR
    TMP_DIR="$(mktemp -d)"

    # Download
    echo -e "  ${YELLOW}[*] Downloading...${NC}"
    curl -L --progress-bar -o "$TMP_DIR/$ASSET_FILENAME" "$ASSET_URL" || {
        echo -e "  ${RED}[!] Download failed for $LABEL${NC}"
        rm -rf "$TMP_DIR"
        return 1
    }
    echo ""

    # Extract
    local EXTRACT_DIR="$TMP_DIR/extracted"
    mkdir -p "$EXTRACT_DIR"

    echo -e "  ${YELLOW}[*] Extracting...${NC}"
    if [ "$ARCHIVE_TYPE" = "tar.gz" ]; then
        # Strip the top-level versioned folder (llama-bXXXX/)
        tar -xzf "$TMP_DIR/$ASSET_FILENAME" \
            -C "$EXTRACT_DIR" \
            --strip-components=1 2>/dev/null || {
            # Fallback: extract as-is then flatten
            tar -xzf "$TMP_DIR/$ASSET_FILENAME" -C "$EXTRACT_DIR" || {
                echo -e "  ${RED}[!] Extraction failed for $LABEL${NC}"
                rm -rf "$TMP_DIR"
                return 1
            }
            local INNER
            INNER=$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)
            if [ -n "$INNER" ]; then
                mv "$INNER"/* "$EXTRACT_DIR/" 2>/dev/null || true
                rmdir "$INNER" 2>/dev/null || true
            fi
        }
    elif [ "$ARCHIVE_TYPE" = "zip" ]; then
        if command -v unzip &>/dev/null; then
            unzip -q "$TMP_DIR/$ASSET_FILENAME" -d "$EXTRACT_DIR" || {
                echo -e "  ${RED}[!] Extraction (zip) failed for $LABEL${NC}"
                rm -rf "$TMP_DIR"
                return 1
            }
        else
            echo -e "  ${YELLOW}[~] 'unzip' not found — skipping $LABEL zip extraction${NC}"
            echo -e "  ${DIM}    Install unzip: sudo pacman -S unzip  OR  sudo apt install unzip${NC}"
            rm -rf "$TMP_DIR"
            return 0
        fi
    fi

    echo -e "  ${DIM} Extracted files:${NC}"
    ls -lh "$EXTRACT_DIR" | tail -n +2 | awk '{printf "     %-42s %s\n", $NF, $5}'
    echo ""

    # Install all files to destination
    mkdir -p "$BIN_DEST"
    cp -r "$EXTRACT_DIR"/. "$BIN_DEST/"

    # Fix permissions
    find "$BIN_DEST" -maxdepth 1 -type f ! -name "*.*"   -exec chmod +x {} \; 2>/dev/null || true
    find "$BIN_DEST" -maxdepth 1 -type f -name "*.so*"   -exec chmod 755 {} \; 2>/dev/null || true
    find "$BIN_DEST" -maxdepth 1 -type f -name "*.dylib" -exec chmod 755 {} \; 2>/dev/null || true

    # Rename llama-server / llama-server.exe → canonical name
    if [ -f "$BIN_DEST/llama-server" ]; then
        cp "$BIN_DEST/llama-server" "$BIN_DEST/$BIN_FINAL"
        chmod +x "$BIN_DEST/$BIN_FINAL"
        echo -e "  ${GREEN}[✓] Renamed  :${NC} llama-server → $BIN_FINAL"
    elif [ -f "$BIN_DEST/llama-server.exe" ]; then
        cp "$BIN_DEST/llama-server.exe" "$BIN_DEST/$BIN_FINAL"
        echo -e "  ${GREEN}[✓] Renamed  :${NC} llama-server.exe → $BIN_FINAL"
    else
        echo -e "  ${RED}[!] llama-server binary not found in extracted files for $LABEL!${NC}"
        ls -lh "$BIN_DEST"
        rm -rf "$TMP_DIR"
        return 1
    fi

    echo -e "  ${GREEN}[✓] $LABEL installed successfully${NC}"
    rm -rf "$TMP_DIR"
    echo ""
}

# ── Create required directories ───────────────────────────────────────────────
mkdir -p "$SCRIPT_DIR/models"
mkdir -p "$SCRIPT_DIR/ui"

# ── Install all platforms ─────────────────────────────────────────────────────
# Format: install_platform LABEL GREP_PATTERN BIN_DEST BIN_FINAL ARCHIVE_TYPE

install_platform \
    "Linux x64" \
    "ubuntu-x64\.tar\.gz" \
    "$SCRIPT_DIR/bin/linux/linux_x64" \
    "llama-server-linux-x64" \
    "tar.gz"

install_platform \
    "Linux arm64" \
    "ubuntu-arm64\.tar\.gz" \
    "$SCRIPT_DIR/bin/linux/linux_arm64" \
    "llama-server-linux-arm" \
    "tar.gz"

# Windows zip — extracted on Linux for cross-platform USB drive use.
# DLLs + exe will be placed in bin/windows/ so they work when run on Windows.
install_platform \
    "Windows x64 (CPU)" \
    "win-cpu-x64\.zip" \
    "$SCRIPT_DIR/bin/windows" \
    "llama-server-win.exe" \
    "zip"

install_platform \
    "macOS arm64 (Apple Silicon)" \
    "macos-arm64\.tar\.gz" \
    "$SCRIPT_DIR/bin/mac/mac_arm64" \
    "llama-server-mac-arm" \
    "tar.gz"

install_platform \
    "macOS x64 (Intel)" \
    "macos-x64\.tar\.gz" \
    "$SCRIPT_DIR/bin/mac/mac_x64" \
    "llama-server-mac-x64" \
    "tar.gz"

# ── Final summary ─────────────────────────────────────────────────────────────
echo -e "${GREEN} ╔═══════════════════════════════════════════╗${NC}"
echo -e "${GREEN} ║      All Platforms Installed!             ║${NC}"
echo -e "${GREEN} ╚═══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Release : ${CYAN}$RELEASE_TAG${NC}"
echo ""
echo -e "  ${BOLD}Directory layout:${NC}"
echo -e "  ${DIM}bin/linux/linux_x64/   → llama-server-linux-x64  + .so libs${NC}"
echo -e "  ${DIM}bin/linux/linux_arm64/ → llama-server-linux-arm   + .so libs${NC}"
echo -e "  ${DIM}bin/mac/mac_arm64/     → llama-server-mac-arm     + .dylib libs${NC}"
echo -e "  ${DIM}bin/mac/mac_x64/       → llama-server-mac-x64     + .dylib libs${NC}"
echo -e "  ${DIM}bin/windows/           → llama-server-win.exe     + .dll files${NC}"
echo ""
echo " Next steps:"
echo "   1. Drop a .gguf model into:  models/"
echo "      Grab one from https://huggingface.co  (Q4_K_M recommended)"
echo "   2. Linux/macOS → run:  ./start.sh"
echo "      Windows     → run:  start.bat"
echo ""

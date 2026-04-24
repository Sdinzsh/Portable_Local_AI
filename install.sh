#!/usr/bin/env bash
# PortableAI — Universal Installer (Linux / macOS)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Banner ────────────────────────────────────────────────────────────────────
clear
echo -e "${CYAN}"
echo " ╔═══════════════════════════════════════════╗"
echo " ║   PortableAI — Universal Installer        ║"
echo " ║   Downloads llama.cpp for any platform    ║"
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

# ── Platform definitions ──────────────────────────────────────────────────────
# Each entry: "LABEL|ASSET_GREP|BIN_DEST|BIN_FINAL|ARCHIVE_TYPE"
PLATFORMS=(
    "Linux x64 (most PCs/servers)|ubuntu-x64\.tar\.gz|bin/linux/linux_x64|llama-server-linux-x64|tar.gz"
    "Linux arm64 (Raspberry Pi, ARM servers)|ubuntu-arm64\.tar\.gz|bin/linux/linux_arm64|llama-server-linux-arm|tar.gz"
    "macOS arm64 (Apple Silicon M1/M2/M3)|macos-arm64\.tar\.gz|bin/mac/mac_arm64|llama-server-mac-arm|tar.gz"
    "macOS x64 (Intel Mac)|macos-x64\.tar\.gz|bin/mac/mac_x64|llama-server-mac-x64|tar.gz"
    "Windows x64 (CPU)|win-cpu-x64\.zip|bin/windows|llama-server-win.exe|zip"
)

PLATFORM_COUNT=${#PLATFORMS[@]}

# ── Platform selection menu ───────────────────────────────────────────────────
echo -e " ${BOLD}Select which platform(s) to install:${NC}"
echo ""

for i in "${!PLATFORMS[@]}"; do
    IFS='|' read -r LABEL _ _ _ _ <<< "${PLATFORMS[$i]}"
    printf "   ${BOLD}[%d]${NC} %s\n" "$((i+1))" "$LABEL"
done

echo ""
echo -e "   ${BOLD}[A]${NC} All platforms (for a shared USB drive)"
echo -e "   ${BOLD}[Q]${NC} Quit"
echo ""
echo -e " ${DIM}Tip: enter multiple numbers separated by spaces (e.g. 1 3)${NC}"
echo ""

SELECTED_INDICES=()

while true; do
    read -rp " Your choice: " RAW_CHOICE

    # Normalize to uppercase for single-letter checks
    UPPER_CHOICE="${RAW_CHOICE^^}"

    if [[ "$UPPER_CHOICE" == "Q" ]]; then
        echo ""
        echo " Aborted."
        exit 0
    fi

    if [[ "$UPPER_CHOICE" == "A" ]]; then
        SELECTED_INDICES=()
        for i in "${!PLATFORMS[@]}"; do
            SELECTED_INDICES+=("$i")
        done
        break
    fi

    # Parse space-separated numbers
    VALID=true
    TMP_INDICES=()
    for TOKEN in $RAW_CHOICE; do
        if [[ "$TOKEN" =~ ^[0-9]+$ ]] \
            && [ "$TOKEN" -ge 1 ] \
            && [ "$TOKEN" -le "$PLATFORM_COUNT" ]; then
            TMP_INDICES+=("$((TOKEN-1))")
        else
            echo -e "${RED} [!] Invalid option: '$TOKEN'. Enter numbers 1-$PLATFORM_COUNT, A, or Q.${NC}"
            VALID=false
            break
        fi
    done

    if $VALID && [ "${#TMP_INDICES[@]}" -gt 0 ]; then
        SELECTED_INDICES=("${TMP_INDICES[@]}")
        break
    elif $VALID; then
        echo -e "${RED} [!] No selection made. Try again.${NC}"
    fi
done

# ── Show what will be installed ───────────────────────────────────────────────
echo ""
echo -e " ${GREEN}[✓] Will install:${NC}"
for idx in "${SELECTED_INDICES[@]}"; do
    IFS='|' read -r LABEL _ BIN_DEST _ _ <<< "${PLATFORMS[$idx]}"
    echo -e "     • $LABEL  ${DIM}→ $BIN_DEST/${NC}"
done
echo ""

# ── Fetch latest release JSON (once, shared across all installs) ──────────────
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

# ── Create base directories ───────────────────────────────────────────────────
mkdir -p "$SCRIPT_DIR/models"
mkdir -p "$SCRIPT_DIR/ui"

# ── Helper: install one platform ──────────────────────────────────────────────
install_platform() {
    local LABEL="$1"
    local ASSET_GREP="$2"
    local BIN_DEST="$SCRIPT_DIR/$3"
    local BIN_FINAL="$4"
    local ARCHIVE_TYPE="$5"

    # Header box — pad to fixed width
    local PAD=$(( 43 - ${#LABEL} ))
    [ "$PAD" -lt 0 ] && PAD=0
    echo -e "${CYAN} ┌─────────────────────────────────────────────┐${NC}"
    printf "${CYAN} │  %-45b│${NC}\n" "Installing: ${BOLD}$LABEL${NC}${CYAN}"
    echo -e "${CYAN} └─────────────────────────────────────────────┘${NC}"

    # ── Find matching asset URL ────────────────────────────────────────────────
    local ASSET_URL
    ASSET_URL=$(echo "$ALL_URLS" \
        | grep -E "$ASSET_GREP" \
        | grep -iv "cuda\|vulkan\|rocm\|kompute\|sycl\|opencl\|mpi\|openvino\|openeuler\|kleidiai" \
        | head -1 || true)

    if [ -z "$ASSET_URL" ]; then
        echo -e "  ${YELLOW}[~] No matching asset found for '$LABEL' — skipping.${NC}"
        echo -e "  ${DIM}    Pattern: $ASSET_GREP${NC}"
        echo ""
        echo " Available non-GPU assets (for reference):"
        echo "$ALL_URLS" \
            | grep -iv "cuda\|vulkan\|rocm\|kompute\|sycl\|opencl\|openvino\|openeuler" \
            | while read -r url; do echo "     $(basename "$url")"; done
        echo ""
        return 0
    fi

    local ASSET_FILENAME
    ASSET_FILENAME="$(basename "$ASSET_URL")"
    echo -e "  ${GREEN}[✓] Asset    :${NC} $ASSET_FILENAME"
    echo -e "  ${GREEN}[✓] Dest dir :${NC} $BIN_DEST"

    # ── Download ───────────────────────────────────────────────────────────────
    local TMP_DIR
    TMP_DIR="$(mktemp -d)"

    echo -e "  ${YELLOW}[*] Downloading...${NC}"
    curl -L --progress-bar -o "$TMP_DIR/$ASSET_FILENAME" "$ASSET_URL" || {
        echo -e "  ${RED}[!] Download failed for '$LABEL'.${NC}"
        rm -rf "$TMP_DIR"
        return 1
    }
    echo ""

    # ── Extract ────────────────────────────────────────────────────────────────
    local EXTRACT_DIR="$TMP_DIR/extracted"
    mkdir -p "$EXTRACT_DIR"

    echo -e "  ${YELLOW}[*] Extracting all files...${NC}"

    if [ "$ARCHIVE_TYPE" = "tar.gz" ]; then
        # --strip-components=1 removes the versioned top-level folder (llama-bXXXX/)
        if ! tar -xzf "$TMP_DIR/$ASSET_FILENAME" \
                -C "$EXTRACT_DIR" \
                --strip-components=1 2>/dev/null; then
            # Fallback: extract verbatim then flatten
            tar -xzf "$TMP_DIR/$ASSET_FILENAME" -C "$EXTRACT_DIR" || {
                echo -e "  ${RED}[!] Extraction failed for '$LABEL'.${NC}"
                rm -rf "$TMP_DIR"
                return 1
            }
            local INNER
            INNER=$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)
            if [ -n "$INNER" ]; then
                mv "$INNER"/* "$EXTRACT_DIR/" 2>/dev/null || true
                rmdir "$INNER" 2>/dev/null || true
            fi
        fi

    elif [ "$ARCHIVE_TYPE" = "zip" ]; then
        if command -v unzip &>/dev/null; then
            unzip -q "$TMP_DIR/$ASSET_FILENAME" -d "$EXTRACT_DIR" || {
                echo -e "  ${RED}[!] Zip extraction failed for '$LABEL'.${NC}"
                rm -rf "$TMP_DIR"
                return 1
            }
            # Windows zips may or may not have a versioned subfolder — flatten if so
            local INNER_ZIP
            INNER_ZIP=$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)
            if [ -n "$INNER_ZIP" ] && [ ! -f "$EXTRACT_DIR/llama-server.exe" ]; then
                mv "$INNER_ZIP"/* "$EXTRACT_DIR/" 2>/dev/null || true
                rmdir "$INNER_ZIP" 2>/dev/null || true
            fi
        else
            echo -e "  ${YELLOW}[~] 'unzip' not found — cannot extract Windows zip on this system.${NC}"
            echo -e "  ${DIM}    sudo pacman -S unzip   OR   sudo apt install unzip${NC}"
            rm -rf "$TMP_DIR"
            return 0
        fi
    fi

    # Show what was extracted
    echo -e "  ${DIM} Extracted files:${NC}"
    ls -lh "$EXTRACT_DIR" | tail -n +2 \
        | awk '{printf "     %-44s %s\n", $NF, $5}'
    echo ""

    # ── Install ALL files to destination ──────────────────────────────────────
    # llama-server depends on libllama.so / libggml*.so / *.dylib / *.dll
    # placed alongside it — we copy everything so it's fully self-contained.
    mkdir -p "$BIN_DEST"
    cp -r "$EXTRACT_DIR"/. "$BIN_DEST/"

    # Fix permissions
    find "$BIN_DEST" -maxdepth 1 -type f ! -name "*.*"   -exec chmod +x {} \; 2>/dev/null || true
    find "$BIN_DEST" -maxdepth 1 -type f -name "*.so*"   -exec chmod 755 {} \; 2>/dev/null || true
    find "$BIN_DEST" -maxdepth 1 -type f -name "*.dylib" -exec chmod 755 {} \; 2>/dev/null || true

    # ── Rename llama-server → canonical name ──────────────────────────────────
    if [ -f "$BIN_DEST/llama-server" ]; then
        cp "$BIN_DEST/llama-server" "$BIN_DEST/$BIN_FINAL"
        chmod +x "$BIN_DEST/$BIN_FINAL"
        echo -e "  ${GREEN}[✓] Renamed  :${NC} llama-server → $BIN_FINAL"
    elif [ -f "$BIN_DEST/llama-server.exe" ]; then
        cp "$BIN_DEST/llama-server.exe" "$BIN_DEST/$BIN_FINAL"
        echo -e "  ${GREEN}[✓] Renamed  :${NC} llama-server.exe → $BIN_FINAL"
    else
        echo -e "  ${RED}[!] llama-server binary not found in extracted archive for '$LABEL'!${NC}"
        echo "  Contents of $BIN_DEST:"
        ls -lh "$BIN_DEST"
        rm -rf "$TMP_DIR"
        return 1
    fi

    echo -e "  ${GREEN}[✓] $LABEL — done!${NC}"
    rm -rf "$TMP_DIR"
    echo ""
}

# ── Run installs for selected platforms ───────────────────────────────────────
FAILED=()

for idx in "${SELECTED_INDICES[@]}"; do
    IFS='|' read -r LABEL ASSET_GREP BIN_DEST BIN_FINAL ARCHIVE_TYPE <<< "${PLATFORMS[$idx]}"
    if ! install_platform "$LABEL" "$ASSET_GREP" "$BIN_DEST" "$BIN_FINAL" "$ARCHIVE_TYPE"; then
        FAILED+=("$LABEL")
    fi
done

# ── Final summary ─────────────────────────────────────────────────────────────
echo -e "${GREEN} ╔═══════════════════════════════════════════╗${NC}"
if [ "${#FAILED[@]}" -eq 0 ]; then
    echo -e "${GREEN} ║  ✅  Installation Complete!               ║${NC}"
else
    echo -e "${YELLOW} ║  ⚠   Installation Complete (with errors)  ║${NC}"
fi
echo -e "${GREEN} ╚═══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Release : ${CYAN}$RELEASE_TAG${NC}"
echo ""

echo -e "  ${BOLD}Installed:${NC}"
for idx in "${SELECTED_INDICES[@]}"; do
    IFS='|' read -r LABEL _ BIN_DEST BIN_FINAL _ <<< "${PLATFORMS[$idx]}"
    FULL_PATH="$SCRIPT_DIR/$BIN_DEST/$BIN_FINAL"
    if [ -f "$FULL_PATH" ]; then
        echo -e "   ${GREEN}✓${NC}  $LABEL"
        echo -e "       ${DIM}→ $BIN_DEST/$BIN_FINAL${NC}"
    else
        echo -e "   ${RED}✗${NC}  $LABEL  ${RED}(failed)${NC}"
    fi
done

if [ "${#FAILED[@]}" -gt 0 ]; then
    echo ""
    echo -e "  ${RED}Failed platforms:${NC}"
    for f in "${FAILED[@]}"; do
        echo -e "   ${RED}✗  $f${NC}"
    done
fi

echo ""
echo " Next steps:"
echo "   1. Drop a .gguf model into:  models/"
echo "      Get one from https://huggingface.co  (Q4_K_M recommended)"
echo "   2. Linux/macOS → ./start.sh"
echo "      Windows     →  start.bat"
echo ""

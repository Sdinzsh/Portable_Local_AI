#!/usr/bin/env bash
# PortableAI — Universal Installer (Linux / macOS)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

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
        echo "     Manjaro/CachyOS/Arch : sudo pacman -S $cmd"
        echo "     Ubuntu/Debian        : sudo apt install $cmd"
        exit 1
    fi
done

# ── Platform definitions ──────────────────────────────────────────────────────

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
    UPPER_CHOICE="${RAW_CHOICE^^}"

    if [[ "$UPPER_CHOICE" == "Q" ]]; then echo ""; echo " Aborted."; exit 0; fi

    if [[ "$UPPER_CHOICE" == "A" ]]; then
        SELECTED_INDICES=(); for i in "${!PLATFORMS[@]}"; do SELECTED_INDICES+=("$i"); done
        break
    fi

    VALID=true; TMP_INDICES=()
    for TOKEN in $RAW_CHOICE; do
        if [[ "$TOKEN" =~ ^[0-9]+$ ]] && [ "$TOKEN" -ge 1 ] && [ "$TOKEN" -le "$PLATFORM_COUNT" ]; then
            TMP_INDICES+=("$((TOKEN-1))")
        else
            echo -e "${RED} [!] Invalid: '$TOKEN'. Enter 1-$PLATFORM_COUNT, A, or Q.${NC}"
            VALID=false; break
        fi
    done

    if $VALID && [ "${#TMP_INDICES[@]}" -gt 0 ]; then
        SELECTED_INDICES=("${TMP_INDICES[@]}"); break
    elif $VALID; then
        echo -e "${RED} [!] No selection made. Try again.${NC}"
    fi
done

echo ""
echo -e " ${GREEN}[✓] Will install:${NC}"
for idx in "${SELECTED_INDICES[@]}"; do
    IFS='|' read -r LABEL _ BIN_DEST _ _ <<< "${PLATFORMS[$idx]}"
    echo -e "     • $LABEL  ${DIM}→ $BIN_DEST/${NC}"
done
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

RELEASE_TAG=$(echo "$RELEASE_JSON" | grep '"tag_name"' | head -1 \
    | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
if [ -z "$RELEASE_TAG" ]; then
    echo -e "${RED} [!] Could not parse release tag. GitHub may be rate-limiting.${NC}"
    echo "$RELEASE_JSON" | head -c 400; exit 1
fi
echo -e " ${GREEN}[✓] Latest release :${NC} $RELEASE_TAG"
echo ""

ALL_URLS=$(echo "$RELEASE_JSON" \
    | grep '"browser_download_url"' \
    | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')
if [ -z "$ALL_URLS" ]; then
    echo -e "${RED} [!] No download URLs found (rate-limited?). Try again in a few minutes.${NC}"
    exit 1
fi

mkdir -p "$SCRIPT_DIR/models" "$SCRIPT_DIR/ui"

# ── Helper: resolve symlinks inside a directory ───────────────────────────────

_resolve_symlinks() {
    local src="$1"
    local dst="$2"
    local changed=0

    for lnk in "$src"/*; do
        [ -L "$lnk" ] || continue
        local fname; fname="$(basename "$lnk")"
        local real
        real="$(readlink -f "$lnk" 2>/dev/null)" \
            || real="$(realpath "$lnk" 2>/dev/null)" \
            || continue
        [ -f "$real" ] || continue

        # Replace the symlink (or missing file) in dst with the real bytes
        cp "$real" "$dst/$fname"
        changed=$(( changed + 1 ))
    done

    if [ "$changed" -gt 0 ]; then
        echo -e "  ${DIM}[symlinks→files] resolved $changed .so/.dylib symlink(s) for portability${NC}"
    fi
}

# ── Helper: cross-platform symlink-dereferencing copy ────────────────────────

_copy_deref() {
    local src="$1"
    local dst="$2"
    # -L = dereference symlinks; -R/-r = recursive; prefer -RL then -rL
    if cp -RL "$src"/. "$dst"/ 2>/dev/null; then return 0; fi
    if cp -rL "$src"/. "$dst"/ 2>/dev/null; then return 0; fi
    # Final fallback: plain copy then post-process symlinks
    cp -r "$src"/. "$dst"/
    _resolve_symlinks "$src" "$dst"
}

# ── Helper: install one platform ─────────────────────────────────────────────
install_platform() {
    local LABEL="$1"
    local ASSET_GREP="$2"
    local BIN_DEST="$SCRIPT_DIR/$3"
    local BIN_FINAL="$4"
    local ARCHIVE_TYPE="$5"

    echo -e "${CYAN} ┌─────────────────────────────────────────────┐${NC}"
    printf  "${CYAN} │  Installing: ${BOLD}%-31s${NC}${CYAN} │${NC}\n" "$LABEL"
    echo -e "${CYAN} └─────────────────────────────────────────────┘${NC}"

    # ── Find matching asset URL ───────────────────────────────────────────────
    local ASSET_URL
    ASSET_URL=$(echo "$ALL_URLS" \
        | grep -E "$ASSET_GREP" \
        | grep -iv "cuda\|vulkan\|rocm\|kompute\|sycl\|opencl\|mpi\|openvino\|openeuler\|kleidiai" \
        | head -1 || true)

    if [ -z "$ASSET_URL" ]; then
        echo -e "  ${YELLOW}[~] No matching asset for '$LABEL' — skipping.${NC}"
        echo -e "  ${DIM}    Pattern searched: $ASSET_GREP${NC}"
        echo ""
        echo "  Available CPU-only assets (for reference):"
        echo "$ALL_URLS" \
            | grep -iv "cuda\|vulkan\|rocm\|kompute\|sycl\|opencl\|openvino\|openeuler" \
            | while read -r u; do echo "     $(basename "$u")"; done
        echo ""; return 0
    fi

    local ASSET_FILENAME; ASSET_FILENAME="$(basename "$ASSET_URL")"
    echo -e "  ${GREEN}[✓] Asset    :${NC} $ASSET_FILENAME"
    echo -e "  ${GREEN}[✓] Dest dir :${NC} $BIN_DEST"

    # ── Download into a temp dir on the system partition (never on USB) ───────
    local TMP_DIR; TMP_DIR="$(mktemp -d)"   # always in /tmp — always writable + exec

    echo -e "  ${YELLOW}[*] Downloading...${NC}"
    curl -L --progress-bar -o "$TMP_DIR/$ASSET_FILENAME" "$ASSET_URL" || {
        echo -e "  ${RED}[!] Download failed for '$LABEL'.${NC}"
        rm -rf "$TMP_DIR"; return 1
    }
    echo ""

    # ── Extract into temp (temp is always on exec FS) ─────────────────────────
    local EXTRACT_DIR="$TMP_DIR/extracted"
    mkdir -p "$EXTRACT_DIR"
    echo -e "  ${YELLOW}[*] Extracting all files...${NC}"

    if [ "$ARCHIVE_TYPE" = "tar.gz" ]; then
        # --strip-components=1 removes the versioned top-level folder (llama-bXXXX/)
        if tar -xzf "$TMP_DIR/$ASSET_FILENAME" \
               -C "$EXTRACT_DIR" \
               --strip-components=1 2>/dev/null; then
            : # success on first try
        else

            local RAW_DIR="$TMP_DIR/raw"; mkdir -p "$RAW_DIR"
            tar -xzf "$TMP_DIR/$ASSET_FILENAME" -C "$RAW_DIR" || {
                echo -e "  ${RED}[!] Extraction failed for '$LABEL'.${NC}"
                rm -rf "$TMP_DIR"; return 1
            }
            # Find the versioned inner directory (llama-bXXXX-bin-...) and flatten
            local INNER
            INNER="$(find "$RAW_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)"
            if [ -n "$INNER" ]; then
                # Safe: copy from inner to EXTRACT_DIR (never mv across the same level)
                cp -r "$INNER"/. "$EXTRACT_DIR/"
            else
                cp -r "$RAW_DIR"/. "$EXTRACT_DIR/"
            fi
        fi

    elif [ "$ARCHIVE_TYPE" = "zip" ]; then
        if ! command -v unzip &>/dev/null; then
            echo -e "  ${YELLOW}[~] 'unzip' not found — cannot extract Windows zip.${NC}"
            echo -e "  ${DIM}    sudo pacman -S unzip   OR   sudo apt install unzip${NC}"
            rm -rf "$TMP_DIR"; return 0
        fi
        unzip -q "$TMP_DIR/$ASSET_FILENAME" -d "$EXTRACT_DIR" || {
            echo -e "  ${RED}[!] Zip extraction failed for '$LABEL'.${NC}"
            rm -rf "$TMP_DIR"; return 1
        }
        # Windows zips sometimes have a versioned subfolder
        local INNER_ZIP
        INNER_ZIP="$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)"
        if [ -n "$INNER_ZIP" ] && [ ! -f "$EXTRACT_DIR/llama-server.exe" ]; then
            local TMP_FLAT="$TMP_DIR/flat"; mkdir -p "$TMP_FLAT"
            cp -r "$INNER_ZIP"/. "$TMP_FLAT/"
            cp -r "$TMP_FLAT"/. "$EXTRACT_DIR/"
        fi
    fi

    echo -e "  ${DIM} Extracted files:${NC}"
    ls -lh "$EXTRACT_DIR" | tail -n +2 | awk '{printf "     %-44s %s\n", $NF, $5}'
    echo ""


    mkdir -p "$BIN_DEST"
    echo -e "  ${YELLOW}[*] Installing files (resolving symlinks for portability)...${NC}"
    _copy_deref "$EXTRACT_DIR" "$BIN_DEST"
    # Belt-and-suspenders: resolve any symlinks cp -L may have missed
    _resolve_symlinks "$EXTRACT_DIR" "$BIN_DEST"


    find "$BIN_DEST" -maxdepth 1 -type f -name "*.so*"   -exec chmod 755 {} \; 2>/dev/null || true
    find "$BIN_DEST" -maxdepth 1 -type f -name "*.dylib" -exec chmod 755 {} \; 2>/dev/null || true
    # All extensionless files (the actual executables)
    find "$BIN_DEST" -maxdepth 1 -type f ! -name "*.*"   -exec chmod +x {} \; 2>/dev/null || true

    # ── Rename llama-server → canonical platform-specific name ───────────────

    local SRC_BIN=""
    for candidate in \
        "$BIN_DEST/llama-server" \
        "$BIN_DEST/llama-server.exe" \
        "$(find "$BIN_DEST" -maxdepth 1 -type f -name "llama-server*" | grep -v "$BIN_FINAL" | head -1)"
    do
        [ -f "$candidate" ] && { SRC_BIN="$candidate"; break; }
    done

    if [ -z "$SRC_BIN" ]; then
        echo -e "  ${RED}[!] llama-server binary not found in archive for '$LABEL'!${NC}"
        echo "      Contents of $BIN_DEST:"
        ls -lh "$BIN_DEST"
        rm -rf "$TMP_DIR"; return 1
    fi

    cp "$SRC_BIN" "$BIN_DEST/$BIN_FINAL"
    chmod +x "$BIN_DEST/$BIN_FINAL"
    echo -e "  ${GREEN}[✓] Renamed  :${NC} $(basename "$SRC_BIN") → $BIN_FINAL"
    echo -e "  ${GREEN}[✓] $LABEL — done!${NC}"
    rm -rf "$TMP_DIR"
    echo ""
}

# ── Run installs ──────────────────────────────────────────────────────────────
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
    echo ""; echo -e "  ${RED}Failed:${NC}"
    for f in "${FAILED[@]}"; do echo -e "   ${RED}✗  $f${NC}"; done
fi

echo ""
echo " Next steps:"
echo "   1. Drop a .gguf model into:  models/"
echo "      Get one at https://huggingface.co  (Q4_K_M recommended)"
echo "   2. Linux/macOS → ./start.sh"
echo "      Windows     →  start.bat"
echo ""

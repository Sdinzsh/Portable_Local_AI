# PortableAI — Plug-and-play Local LLM Server

> Run any GGUF language model locally — no Python, no Docker, no cloud, no install headaches.  
> Works from a USB drive. Runs on Linux, macOS, and Windows. One script to set up everything.

---

## What is this?

PortableAI wraps [llama.cpp](https://github.com/ggml-org/llama.cpp)'s `llama-server` into a zero-dependency portable package. You plug in a USB drive (or clone the repo), drop in a model, and run a single script. A local web UI opens in your browser and you can start chatting — fully offline, fully private.

No Python environment. No package managers. No GPU required.

---

## Features

- **Truly portable** — runs from a USB stick on any machine
- **Cross-platform** — Linux (x64 + arm64), macOS (Intel + Apple Silicon), Windows (x64)
- **Auto-installer** — fetches the correct `llama-server` binary for every platform in one run
- **Model picker** — prompts you to choose when multiple `.gguf` models are present
- **CPU-only** — works on any modern machine without a GPU
- **100% offline** after setup — no data leaves your machine
- **Built-in web UI** — chat interface served directly by `llama-server`
- **LAN sharing** — accessible from any device on the same Wi-Fi at `http://0.0.0.0:8080`

---

## Directory Layout

```
PortableAI/
├── install.sh          ← Linux/macOS installer (all platforms)
├── install.bat         ← Windows installer
├── start.sh            ← Linux/macOS launcher
├── start.bat           ← Windows launcher
├── models/             ← Drop your .gguf model files here
├── ui/                 ← (optional) custom web UI override
└── bin/
    ├── linux/
    │   ├── linux_x64/
    │   │   ├── llama-server-linux-x64   ← renamed server binary
    │   │   ├── libllama.so              ← required shared libs
    │   │   ├── libggml.so
    │   │   └── libggml-cpu.so  ...
    │   └── linux_arm64/
    │       └── llama-server-linux-arm   + .so libs
    ├── mac/
    │   ├── mac_arm64/
    │   │   └── llama-server-mac-arm     + .dylib libs
    │   └── mac_x64/
    │       └── llama-server-mac-x64     + .dylib libs
    └── windows/
        ├── llama-server-win.exe
        └── *.dll                        ← required DLLs
```

---

## Quick Start

### Step 1 — Get a model

Download any `.gguf` model and place it in the `models/` folder.

**Recommended for most machines (4–8 GB RAM):**

> Search [huggingface.co](https://huggingface.co) for any model — filter by `GGUF` format and pick a `Q4_K_M` quantization for the best balance of size and quality.

### Step 2 — Install binaries

**Linux / macOS**
```bash
chmod +x install.sh
./install.sh
```

The installer asks which platform(s) to set up:

```
 Select which platform(s) to install:

   [1] Linux x64 (most PCs/servers)
   [2] Linux arm64 (Raspberry Pi, ARM servers)
   [3] macOS arm64 (Apple Silicon M1/M2/M3)
   [4] macOS x64 (Intel Mac)
   [5] Windows x64 (CPU)

   [A] All platforms (for a shared USB drive)
   [Q] Quit

 Tip: enter multiple numbers separated by spaces (e.g. 1 3)
```

Choose **A** to pre-load all platforms if you're preparing a USB drive that will be used on multiple machines.

**Windows**
```
Double-click install.bat
```

### Step 3 — Start the server

**Linux / macOS**
```bash
chmod +x start.sh
./start.sh
```

**Windows**
```
Double-click start.bat
```

The browser opens automatically at **http://127.0.0.1:8080**

If you have multiple models, you'll be asked to choose one:

```
 [?] Multiple models found — select one:
     ─────────────────────────────────────────────
     [1] mistral-7b-instruct-v0.2.Q4_K_M.gguf     3.8G
     [2] llama-3.2-3b-instruct-q4_k_m.gguf         1.9G

 Enter number [1-2]:
```

---

## Requirements

### Runtime
| Platform | Requirement |
|---|---|
| Linux | glibc 2.17+ (any modern distro) |
| macOS | 11.0+ (Big Sur or later) |
| Windows | Windows 10 (build 17063+), [Visual C++ Redistributable](https://aka.ms/vs/17/release/vc_redist.x64.exe) |

### For install.sh
| Tool | Notes |
|---|---|
| `curl` | Pre-installed on most systems |
| `tar` | Pre-installed on all Linux/macOS |
| `unzip` | Only needed for Windows zip on Linux: `sudo pacman -S unzip` |

### Hardware (minimum)
| RAM | Recommended model size |
|---|---|
| 4 GB | 1B–3B models (Q4_K_M) |
| 8 GB | 7B models (Q4_K_M) |
| 16 GB | 13B models (Q4_K_M) |
| 32 GB | 30B+ models (Q4_K_M) |

---

## How It Works

```
install.sh / install.bat
        │
        ├── Queries GitHub API for latest llama.cpp release
        ├── Downloads the correct archive per platform:
        │       Linux x64   → llama-bXXXX-bin-ubuntu-x64.tar.gz
        │       Linux arm64 → llama-bXXXX-bin-ubuntu-arm64.tar.gz
        │       macOS arm64 → llama-bXXXX-bin-macos-arm64.tar.gz
        │       macOS x64   → llama-bXXXX-bin-macos-x64.tar.gz
        │       Windows x64 → llama-bXXXX-bin-win-cpu-x64.zip
        ├── Extracts ALL files (binary + shared libs / DLLs)
        └── Renames llama-server → platform-specific canonical name

start.sh / start.bat
        │
        ├── Scans models/ for .gguf files
        ├── Prompts for selection if > 1 model found
        ├── Detects OS + architecture
        ├── Sets LD_LIBRARY_PATH (Linux) / DYLD_LIBRARY_PATH (macOS)
        │   so shared libs next to the binary are always found
        └── Launches llama-server on port 8080
```

> **Why copy all the `.so` / `.dll` files?**  
> `llama-server` dynamically links against `libllama`, `libggml`, `libggml-cpu` and others. Copying only the executable would cause an immediate crash with a "shared library not found" error. The installer copies the entire archive contents into the bin directory, and `start.sh` sets `LD_LIBRARY_PATH` to that directory so the binary is fully self-contained without touching any system paths.

---

## Configuration

The server starts with sensible defaults. To customize, edit the `exec "$BIN"` block at the bottom of `start.sh` / `start.bat`:

```bash
exec "$BIN" \
    -m "$MODEL"      \   # model file path (set automatically)
    -c 4096          \   # context window size (tokens)
    -t "$THREADS"    \   # CPU threads (auto: nproc - 1)
    --port 8080      \   # HTTP port
    --host 0.0.0.0       # bind address (0.0.0.0 = LAN accessible)
```

Common tweaks:

| Flag | Example | Effect |
|---|---|---|
| `-c` | `-c 8192` | Larger context (needs more RAM) |
| `-t` | `-t 4` | Fixed thread count |
| `--port` | `--port 9090` | Change the port |
| `--host` | `--host 127.0.0.1` | Localhost only (disable LAN) |
| `-ngl` | `-ngl 35` | Offload layers to GPU (if available) |

Full flag reference: `./bin/linux/linux_x64/llama-server-linux-x64 --help`

---

## Accessing from Other Devices

While the server is running, any device on the same network can access the UI:

1. Find your machine's local IP: `ip addr` (Linux) / `ipconfig` (Windows)
2. Open `http://192.168.x.x:8080` on the other device

---

## Troubleshooting

**`llama-server: error while loading shared libraries: libllama.so`**  
The shared libs are missing from the bin directory. Re-run `install.sh` — it copies all files from the archive, not just the binary.

**Binary not found / install.sh stops silently after printing the release tag**  
GitHub API rate-limited the request (60 requests/hour for unauthenticated IPs). Wait a few minutes and try again.

**`VCRUNTIME140_1.dll` not found (Windows)**  
Install the [Visual C++ Redistributable](https://aka.ms/vs/17/release/vc_redist.x64.exe) and re-run `start.bat`.

**Model loads but responses are very slow**  
Use a smaller or more quantized model (e.g., `Q2_K` instead of `Q8_0`). Reduce context with `-c 2048`.

**Port 8080 already in use**  
Change `--port 8080` to another port (e.g. `--port 9090`) in `start.sh` / `start.bat`.

---

## Updating llama.cpp

Just re-run the installer. It always fetches the **latest** release from GitHub:

```bash
./install.sh   # picks what to update, overwrites existing binaries
```

---

## Project Structure

```
Portable_Local_AI/
├── install.sh      Universal installer — Linux/macOS, all platforms
├── install.bat     Windows installer
├── start.sh        Launcher — Linux/macOS
├── start.bat       Launcher — Windows
├── models/         Your .gguf model files go here
├── ui/             Optional: override the built-in web UI
└── bin/            Auto-populated by installer
```

---

## Credits

- **[llama.cpp](https://github.com/ggml-org/llama.cpp)** by ggml-org — the inference engine powering everything
- Models from **[HuggingFace](https://huggingface.co)** — community-converted GGUF weights

---

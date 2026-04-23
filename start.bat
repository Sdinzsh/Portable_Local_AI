@echo off
setlocal EnableDelayedExpansion
title PortableAI
cd /d "%~dp0"

echo.
echo  ╔═══════════════════════════════════════════╗
echo  ║      PortableAI  —  Zero Dependency       ║
echo  ║      Plug-and-play Local LLM Server       ║
echo  ╚═══════════════════════════════════════════╝
echo.

:: ── Find model ──────────────────────────────────────────────────────────────
set "MODEL="
for %%F in (models\*.gguf) do (
    if not defined MODEL set "MODEL=%%F"
)
if not defined MODEL (
    echo  [!] No .gguf model found in models\
    echo      Download one from https://huggingface.co
    echo      Recommended: any Q4_K_M model
    pause
    exit /b 1
)

:: ── Find binary ──────────────────────────────────────────────────────────────
set "BIN=bin\windows\llama-server-win.exe"
if not exist "%BIN%" (
    echo  [!] Binary not found: %BIN%
    echo      First run the install.bat
    pause
    exit /b 1
)

:: ── Thread count (all cores minus 1) ────────────────────────────────────────
set /a THREADS=%NUMBER_OF_PROCESSORS%-1
if %THREADS% LSS 1 set THREADS=1

echo  [+] Model  : %MODEL%
echo  [+] Threads: %THREADS%
echo  [+] UI     : http://127.0.0.1:8080
echo  [+] LAN    : http://0.0.0.0:8080  (same WiFi)
echo.
echo  Press Ctrl+C to stop.
echo  ─────────────────────────────────────────────

:: Open browser after 2s
start "" /min cmd /c "timeout /t 2 /nobreak >nul && start http://127.0.0.1:8080"

"%BIN%" ^
    -m "%MODEL%" ^
    -c 4096 ^
    -t %THREADS% ^
    --port 8080 ^
    --host 0.0.0.0 ^
    --path ui

pause

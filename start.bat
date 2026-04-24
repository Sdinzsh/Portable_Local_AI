@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo.
echo ---------------------------------------------
echo    PortableAI - Zero Dependency
echo    Plug-and-play Local LLM Server
echo ---------------------------------------------
echo.

:: ---------- Check for Visual C++ Runtime (VCRUNTIME140_1.dll) ----------
if not exist "%SystemRoot%\System32\VCRUNTIME140_1.dll" (
    echo [!] Missing: VCRUNTIME140_1.dll
    echo.
    echo The llama server requires Microsoft Visual C++ Redistributable.
    echo Please download and install it from:
    echo     https://aka.ms/vs/17/release/vc_redist.x64.exe
    echo.
    echo After installation, run this script again.
    pause
    exit /b 1
)

:: ---------- Collect all .gguf models in models\ ----------
set "MODEL_COUNT=0"
for %%f in ("models\*.gguf") do (
    set /a MODEL_COUNT+=1
    set "MODEL_!MODEL_COUNT!=%%f"
)

if %MODEL_COUNT% equ 0 (
    echo [!] No .gguf model found in models\
    echo     Download one from https://huggingface.co
    echo     Recommended: any Q4_K_M quantization
    pause
    exit /b 1
)

:: ---------- Model selection ----------
if %MODEL_COUNT% equ 1 (
    set "MODEL=!MODEL_1!"
    for %%m in ("!MODEL!") do set "MODEL_NAME=%%~nxm"
    echo [+] Using model: !MODEL_NAME!
) else (
    echo [?] Multiple models found - select one:
    echo     ------------------------------------
    for /l %%i in (1,1,%MODEL_COUNT%) do (
        for %%m in ("!MODEL_%%i!") do (
            set "NAME=%%~nxm"
            set "SIZE=%%~zm"
        )
        set /a SIZE_MB=!SIZE! / 1048576
        echo     [%%i] !NAME!   (!SIZE_MB! MB)
    )
    echo.
    :CHOOSE_LOOP
    set "CHOICE="
    set /p "CHOICE= Enter number [1-%MODEL_COUNT%]: "
    if not defined CHOICE goto CHOOSE_LOOP
    set "VALID=0"
    for /l %%i in (1,1,%MODEL_COUNT%) do if "!CHOICE!"=="%%i" set "VALID=1"
    if !VALID! equ 0 (
        echo [!] Invalid. Enter a number between 1 and %MODEL_COUNT%.
        goto CHOOSE_LOOP
    )
    set "MODEL=!MODEL_%CHOICE%!"
    for %%m in ("!MODEL!") do set "MODEL_NAME=%%~nxm"
    echo.
    echo [+] Selected: !MODEL_NAME!
)

:: ---------- Binary path ----------
set "BIN_DIR=bin\windows"
set "BIN=%BIN_DIR%\llama-server-win.exe"

if not exist "%BIN%" (
    echo [!] Binary not found: %BIN%
    echo     Run install.bat first.
    pause
    exit /b 1
)

:: Ensure DLLs next to the binary are found
set "PATH=%BIN_DIR%;%PATH%"

:: ---------- Thread count (logical cores minus 1) ----------
set "CORES=%NUMBER_OF_PROCESSORS%"
if not defined CORES set "CORES=4"
set /a THREADS=%CORES% - 1
if %THREADS% lss 1 set THREADS=1

:: ---------- Launch info ----------
echo.
echo [+] OS       : Windows (%PROCESSOR_ARCHITECTURE%)
echo [+] Threads  : %THREADS%
echo [+] Local UI : http://127.0.0.1:8080
echo [+] LAN      : http://0.0.0.0:8080 (same network)
echo.
echo Press Ctrl+C to stop the server.
echo ------------------------------------

:: ---------- Open browser after 3 seconds ----------
start "" /b cmd /c "timeout /t 3 /nobreak >nul & start http://127.0.0.1:8080"

:: ---------- Start the server ----------
"%BIN%" -m "%MODEL%" -c 4096 -t %THREADS% --port 8080 --host 0.0.0.0

endlocal
exit /b
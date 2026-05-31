@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo.
echo ---------------------------------------------
echo    PortableAI - Universal Installer
echo    Downloads llama.cpp for any platform
echo ---------------------------------------------

:: ── Dependency check ─────────────────────────────────────────────────────────
where curl >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [!] curl not found. Please install curl.
    echo     https://curl.se/windows/
    pause
    exit /b 1
)

where tar >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [!] tar not found. Windows 10 build 17063+ includes it.
    pause
    exit /b 1
)

:: ── Platform definitions ─────────────────────────────────────────────────────
set "PLATFORM_1_LABEL=Linux x64 (most PCs/servers)"
set "PLATFORM_1_ASSET=ubuntu-x64.tar.gz"
set "PLATFORM_1_BIN_DEST=bin\linux\linux_x64"
set "PLATFORM_1_BIN_FINAL=llama-server-linux-x64"
set "PLATFORM_1_ARCHIVE=tar.gz"

set "PLATFORM_2_LABEL=Linux arm64 (Raspberry Pi, ARM servers)"
set "PLATFORM_2_ASSET=ubuntu-arm64.tar.gz"
set "PLATFORM_2_BIN_DEST=bin\linux\linux_arm64"
set "PLATFORM_2_BIN_FINAL=llama-server-linux-arm"
set "PLATFORM_2_ARCHIVE=tar.gz"

set "PLATFORM_3_LABEL=macOS arm64 (Apple Silicon M1/M2/M3)"
set "PLATFORM_3_ASSET=macos-arm64.tar.gz"
set "PLATFORM_3_BIN_DEST=bin\mac\mac_arm64"
set "PLATFORM_3_BIN_FINAL=llama-server-mac-arm"
set "PLATFORM_3_ARCHIVE=tar.gz"

set "PLATFORM_4_LABEL=macOS x64 (Intel Mac)"
set "PLATFORM_4_ASSET=macos-x64.tar.gz"
set "PLATFORM_4_BIN_DEST=bin\mac\mac_x64"
set "PLATFORM_4_BIN_FINAL=llama-server-mac-x64"
set "PLATFORM_4_ARCHIVE=tar.gz"

set "PLATFORM_5_LABEL=Windows x64 (CPU)"
set "PLATFORM_5_ASSET=win-cpu-x64.zip"
set "PLATFORM_5_BIN_DEST=bin\windows"
set "PLATFORM_5_BIN_FINAL=llama-server-win.exe"
set "PLATFORM_5_ARCHIVE=zip"

:: ── Platform selection menu ──────────────────────────────────────────────────
echo Select which platform(s) to install:
echo.
echo    [1] Linux x64 (most PCs/servers)
echo    [2] Linux arm64 (Raspberry Pi, ARM servers)
echo    [3] macOS arm64 (Apple Silicon M1/M2/M3)
echo    [4] macOS x64 (Intel Mac)
echo    [5] Windows x64 (CPU)
echo.
echo    [A] All platforms (for a shared USB drive)
echo    [Q] Quit
echo.
echo Tip: enter multiple numbers separated by spaces (e.g. 1 3)
echo.

set "SELECTED_INDICES="

:SELECT_LOOP
set "RAW_CHOICE="
set /p "RAW_CHOICE= Your choice: "
if not defined RAW_CHOICE goto SELECT_LOOP

if /i "%RAW_CHOICE%"=="Q" (
    echo.
    echo Aborted.
    exit /b 0
)

if /i "%RAW_CHOICE%"=="A" (
    for /l %%i in (1,1,5) do set "SELECTED_INDICES=!SELECTED_INDICES! %%i"
    goto SELECT_DONE
)

set "VALID=1"
for %%t in (%RAW_CHOICE%) do (
    set "TOKEN=%%t"
    set "IS_NUM=1"
    for /f "delims=0123456789" %%n in ("!TOKEN!") do set "IS_NUM=0"
    if !IS_NUM! equ 1 (
        if !TOKEN! geq 1 if !TOKEN! leq 5 (
            set "SELECTED_INDICES=!SELECTED_INDICES! !TOKEN!"
        ) else (
            echo [!] Invalid: '!TOKEN!'. Enter numbers 1-5, A, or Q.
            set "VALID=0"
        )
    ) else (
        echo [!] Invalid: '!TOKEN!'. Enter numbers 1-5, A, or Q.
        set "VALID=0"
    )
)

if !VALID! equ 0 (
    set "SELECTED_INDICES="
    goto SELECT_LOOP
)
if not defined SELECTED_INDICES (
    echo [!] No selection made. Try again.
    goto SELECT_LOOP
)

:SELECT_DONE
set "SELECTED_INDICES=%SELECTED_INDICES:~1%"

echo.
echo [OK] Will install:
for %%i in (%SELECTED_INDICES%) do (
    call set "LABEL=%%PLATFORM_%%i_LABEL%%"
    call set "BIN_DEST=%%PLATFORM_%%i_BIN_DEST%%"
    echo      * !LABEL!  -^> !BIN_DEST!\
)
echo.

:: ── Fetch latest release from GitHub API ────────────────────────────────────
echo [*] Fetching latest llama.cpp release from GitHub API...

set "RELEASE_TAG="
set "RELEASE_URLS_FILE=%TEMP%\llama_release_urls.txt"

powershell -NoProfile -Command ^
    "$rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/ggml-org/llama.cpp/releases/latest' -Headers @{'Accept'='application/vnd.github+json'; 'X-GitHub-Api-Version'='2022-11-28'}; Write-Output $rel.tag_name; foreach ($a in $rel.assets) { Write-Output $a.browser_download_url }" > "%TEMP%\release_output.txt" 2>nul

if %ERRORLEVEL% NEQ 0 (
    echo [!] Failed to reach GitHub API. Check your internet connection.
    pause
    exit /b 1
)

set /p RELEASE_TAG=<"%TEMP%\release_output.txt"

if exist "%RELEASE_URLS_FILE%" del "%RELEASE_URLS_FILE%"
for /f "usebackq skip=1 delims=" %%u in ("%TEMP%\release_output.txt") do (
    echo %%u>> "%RELEASE_URLS_FILE%"
)

if not defined RELEASE_TAG (
    echo [!] Could not parse release tag. GitHub may be rate-limiting.
    type "%TEMP%\release_output.txt"
    pause
    exit /b 1
)
echo [OK] Latest release: %RELEASE_TAG%
echo.

if not exist "models" mkdir "models"
if not exist "ui"     mkdir "ui"

set "FAILED_COUNT=0"
set "FAILED_LIST="

for %%i in (%SELECTED_INDICES%) do (
    call :INSTALL_PLATFORM %%i
    if !ERRORLEVEL! neq 0 (
        set /a FAILED_COUNT+=1
        set "FAILED_LIST=!FAILED_LIST! %%i"
    )
)

:: ── Final summary ────────────────────────────────────────────────────────────
echo ---------------------------------------------
if %FAILED_COUNT% equ 0 (
    echo    Installation Complete!
) else (
    echo    Installation Complete (with errors)
)
echo ---------------------------------------------
echo.
echo   Release: %RELEASE_TAG%
echo.
echo Installed:
for %%i in (%SELECTED_INDICES%) do (
    call set "LABEL=%%PLATFORM_%%i_LABEL%%"
    call set "BIN_DEST=%%PLATFORM_%%i_BIN_DEST%%"
    call set "BIN_FINAL=%%PLATFORM_%%i_BIN_FINAL%%"
    if exist "!BIN_DEST!\!BIN_FINAL!" (
        echo    [OK]   !LABEL!
        echo           -^> !BIN_DEST!\!BIN_FINAL!
    ) else (
        echo    [FAIL] !LABEL! (failed)
    )
)

if %FAILED_COUNT% gtr 0 (
    echo.
    echo Failed platforms:
    for %%i in (%FAILED_LIST%) do (
        call set "LABEL=%%PLATFORM_%%i_LABEL%%"
        echo    - !LABEL!
    )
)

echo.
echo Next steps:
echo    1. Place a .gguf model into the models\ folder
echo       Download from https://huggingface.co  (Q4_K_M recommended)
echo    2. Linux/macOS - ./start.sh
echo       Windows     -  start.bat
echo.
pause
exit /b 0


:: ============================================================
:INSTALL_PLATFORM
setlocal
set "IDX=%1"
call set "LABEL=%%PLATFORM_%IDX%_LABEL%%"
call set "ASSET=%%PLATFORM_%IDX%_ASSET%%"
call set "BIN_DEST=%%PLATFORM_%IDX%_BIN_DEST%%"
call set "BIN_FINAL=%%PLATFORM_%IDX%_BIN_FINAL%%"
call set "ARCHIVE_TYPE=%%PLATFORM_%IDX%_ARCHIVE%%"

echo ---------------------------------------------
echo Installing: !LABEL!
echo ---------------------------------------------

:: ── Find matching asset URL ──────────────────────────────────────────────────
set "ASSET_URL="
for /f "usebackq tokens=*" %%u in ("%RELEASE_URLS_FILE%") do (
    echo %%u | findstr /c:"!ASSET!" >nul
    if not errorlevel 1 (
        echo %%u | findstr /i /v /c:"cuda" /c:"vulkan" /c:"rocm" /c:"kompute" /c:"sycl" /c:"opencl" /c:"mpi" /c:"openvino" /c:"openeuler" /c:"kleidiai" >nul
        if not errorlevel 1 (
            if "!ASSET_URL!"=="" set "ASSET_URL=%%u"
        )
    )
)

if not defined ASSET_URL (
    echo [~] No matching asset for '!LABEL!' - skipping.
    echo     Pattern: !ASSET!
    echo.
    echo Available CPU-only assets:
    findstr /v /i /c:"cuda" /c:"vulkan" /c:"rocm" /c:"kompute" /c:"sycl" /c:"opencl" /c:"openvino" /c:"openeuler" "%RELEASE_URLS_FILE%"
    echo.
    exit /b 0
)

for %%F in ("!ASSET_URL!") do set "ASSET_FILENAME=%%~nxF"
echo [OK] Asset: !ASSET_FILENAME!
echo [OK] Destination: !BIN_DEST!

:: ── Download to TEMP (always NTFS, always exec-capable) ─────────────────────
set "TMP_DOWNLOAD=%TEMP%\!ASSET_FILENAME!"
set "TMP_EXTRACT=%TEMP%\llama_extract_!IDX!"
if exist "!TMP_EXTRACT!" rmdir /s /q "!TMP_EXTRACT!"
mkdir "!TMP_EXTRACT!"

echo [*] Downloading...
curl -L --progress-bar -o "!TMP_DOWNLOAD!" "!ASSET_URL!"
if %ERRORLEVEL% NEQ 0 (
    echo [!] Download failed for '!LABEL!'.
    goto CLEANUP_FAIL
)
echo.

:: ── Extract into TEMP ────────────────────────────────────────────────────────
echo [*] Extracting all files...

if /i "!ARCHIVE_TYPE!"=="zip" (
    powershell -NoProfile -Command "Expand-Archive -Path '!TMP_DOWNLOAD!' -DestinationPath '!TMP_EXTRACT!' -Force" 2>nul
    if %ERRORLEVEL% NEQ 0 (
        echo [!] Zip extraction failed for '!LABEL!'.
        goto CLEANUP_FAIL
    )
    :: FIX [BUG-13]: flatten using a safe intermediate dir, not in-place move
    set "TMP_FLAT=%TEMP%\llama_flat_!IDX!"
    if exist "!TMP_FLAT!" rmdir /s /q "!TMP_FLAT!"
    mkdir "!TMP_FLAT!"
    for /d %%d in ("!TMP_EXTRACT!\*") do (
        :: Check if llama-server.exe is inside a subfolder (versioned zip)
        if not exist "!TMP_EXTRACT!\llama-server.exe" (
            xcopy /e /y /q "%%d\*" "!TMP_FLAT!\" >nul 2>&1
        )
    )
    :: If we flattened anything, merge back
    if exist "!TMP_FLAT!\llama-server.exe" (
        xcopy /e /y /q "!TMP_FLAT!\*" "!TMP_EXTRACT!\" >nul 2>&1
    )
    if exist "!TMP_FLAT!" rmdir /s /q "!TMP_FLAT!"

) else (
    :: tar.gz — try --strip-components=1 first
    tar -xzf "!TMP_DOWNLOAD!" -C "!TMP_EXTRACT!" --strip-components=1 >nul 2>&1
    if %ERRORLEVEL% NEQ 0 (
        :: FIX [BUG-13]: extract into a dedicated raw subdir, never overlap EXTRACT
        set "TMP_RAW=%TEMP%\llama_raw_!IDX!"
        if exist "!TMP_RAW!" rmdir /s /q "!TMP_RAW!"
        mkdir "!TMP_RAW!"
        tar -xzf "!TMP_DOWNLOAD!" -C "!TMP_RAW!" >nul 2>&1
        if %ERRORLEVEL% NEQ 0 (
            echo [!] Extraction failed for '!LABEL!'.
            goto CLEANUP_FAIL
        )
        :: Find and flatten the versioned inner dir safely
        for /d %%d in ("!TMP_RAW!\*") do (
            xcopy /e /y /q "%%d\*" "!TMP_EXTRACT!\" >nul 2>&1
        )
        :: If nothing was in a subdir, copy raw root directly
        xcopy /e /y /q "!TMP_RAW!\*" "!TMP_EXTRACT!\" >nul 2>&1
        if exist "!TMP_RAW!" rmdir /s /q "!TMP_RAW!"
    )
)

echo Extracted files:
dir /b "!TMP_EXTRACT!"
echo.

:: ── FIX : Resolve symlinks in TEMP before copying to destination ──
::
echo [*] Resolving symlinks for filesystem portability...
powershell -NoProfile -Command ^
    "Get-ChildItem '!TMP_EXTRACT!' -Recurse -Force | Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint } | ForEach-Object { try { $link = $_.FullName; $target = $_.Target; if (-not [System.IO.Path]::IsPathRooted($target)) { $target = Join-Path $_.DirectoryName $target }; if (Test-Path $target -PathType Leaf) { $bytes = [System.IO.File]::ReadAllBytes($target); [System.IO.File]::WriteAllBytes($link, $bytes); Write-Host ('[symlink->file] ' + $_.Name) } } catch {} }" 2>nul
echo.

:: ── Copy all files to destination ────────────────────────────────────────────
if not exist "!BIN_DEST!" mkdir "!BIN_DEST!"
xcopy /e /y /q "!TMP_EXTRACT!\*" "!BIN_DEST!\" >nul

:: ── Rename llama-server → canonical name ────────────────────────────────────
if exist "!BIN_DEST!\llama-server.exe" (
    copy /y "!BIN_DEST!\llama-server.exe" "!BIN_DEST!\!BIN_FINAL!" >nul
    echo [OK] Renamed llama-server.exe -^> !BIN_FINAL!
) else if exist "!BIN_DEST!\llama-server" (
    copy /y "!BIN_DEST!\llama-server" "!BIN_DEST!\!BIN_FINAL!" >nul
    echo [OK] Renamed llama-server -^> !BIN_FINAL!
) else (
    echo [!] llama-server binary not found in archive for '!LABEL!'
    echo     Contents of !BIN_DEST!:
    dir /b "!BIN_DEST!"
    goto CLEANUP_FAIL
)

echo [OK] !LABEL! - done!
del "!TMP_DOWNLOAD!" 2>nul
rmdir /s /q "!TMP_EXTRACT!" 2>nul
echo.
exit /b 0

:CLEANUP_FAIL
del "!TMP_DOWNLOAD!" 2>nul
if exist "!TMP_EXTRACT!" rmdir /s /q "!TMP_EXTRACT!" 2>nul
exit /b 1

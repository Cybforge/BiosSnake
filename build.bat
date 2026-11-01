@echo off
cd /d "%~dp0"
echo ========================================================
echo [1/3] Generating BIOS source and 16-bit PCM Audio Banks...
echo ========================================================
python "%~dp0gen_bios.py"
if errorlevel 1 (
    echo [ERROR] Python generator failed!
    pause
    exit /b 1
)

echo ========================================================
echo [2/3] Verifying 256 KB BIOS ROM and Segments...
echo ========================================================
if not exist "%~dp0bios.bin" (
    echo [ERROR] bios.bin was not found!
    pause
    exit /b 1
)

python -c "import os, sys; sz = os.path.getsize(r'%~dp0bios.bin'); sys.exit(0 if sz == 262144 else 1)"
if errorlevel 1 (
    echo [ERROR] Invalid ROM size! Expected 262,144 Bytes.
    pause
    exit /b 1
)
echo [OK] ROM Size Verified: 262,144 Bytes (256.0 KB).

echo ========================================================
echo [3/3] Cybforge Retro BIOS 256 KB Ready!
echo ========================================================
echo [OK] bios.bin successfully generated (262,144 Bytes).

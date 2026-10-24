@echo off
cd /d "%~dp0"
echo ========================================================
echo [1/2] Generating bios.asm...
echo ========================================================
python "%~dp0gen_bios.py"
if errorlevel 1 (
    echo [ERROR] Python generator failed!
    pause
    exit /b 1
)

echo ========================================================
echo [2/2] Assembling with NASM...
echo ========================================================
set "NASM_CMD=nasm"
where nasm >nul 2>nul
if errorlevel 1 (
    if exist "C:\Users\jonas\Documents\Default Project\NASM\nasm-2.16.01\nasm.exe" (
        set "NASM_CMD=C:\Users\jonas\Documents\Default Project\NASM\nasm-2.16.01\nasm.exe"
    )
)

"%NASM_CMD%" -f bin "%~dp0bios.asm" -o "%~dp0bios.bin"
if errorlevel 1 (
    echo [ERROR] Assembly failed!
    pause
    exit /b 1
)
echo [OK] bios.bin successfully generated (65536 Bytes).

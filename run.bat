@echo off
cd /d "%~dp0"
if not exist "%~dp0bios.bin" (
    echo Building bios.bin first...
    call "%~dp0build.bat"
)
if not exist "%~dp0cybfs_nvram.img" (
    echo Creating persistent 64 KB NVRAM/CybFS disk image [cybfs_nvram.img]...
    python -c "open(r'%~dp0cybfs_nvram.img','wb').write(b'\x00'*65536)"
)

echo ========================================================
echo Cybforge Retro BIOS Loader [v2.8 Persistent NVRAM]
echo ========================================================

rem Fast screen geometry detection in 0.01s via Python ctypes
for /f "tokens=1,2" %%a in ('python -c "import ctypes; u=ctypes.windll.user32; print(u.GetSystemMetrics(0), u.GetSystemMetrics(1))" 2^>nul') do (
    set SCREEN_W=%%a
    set SCREEN_H=%%b
)

if "%SCREEN_W%"=="" set SCREEN_W=1920
if "%SCREEN_H%"=="" set SCREEN_H=1080

echo [OK] Screen Detected : %SCREEN_W%x%SCREEN_H%
echo [OK] Persistent Disk : cybfs_nvram.img (ATA Primary Master LBA 0..31)
echo [OK] Display Scaling : Hardware-Accelerated OpenGL Scaling (Retro CRT)
echo Starting Cybforge Retro BIOS in QEMU...
echo ========================================================

set "QEMU_CMD=qemu-system-x86_64"
where qemu-system-x86_64 >nul 2>nul
if errorlevel 1 (
    if exist "C:\Users\jonas\AppData\Local\Programs\QEMU\qemu-system-x86_64.exe" (
        set "QEMU_CMD=C:\Users\jonas\AppData\Local\Programs\QEMU\qemu-system-x86_64.exe"
    )
)

rem Launch with Persistent ATA NVRAM Disk (cybfs_nvram.img), Sound Blaster 16 (16-Bit PCM), and OpenGL display
"%QEMU_CMD%" -bios "%~dp0bios.bin" -drive file="%~dp0cybfs_nvram.img",format=raw,if=ide -audiodev dsound,id=snd0,latency=20000 -machine pc,pcspk-audiodev=snd0 -device sb16,audiodev=snd0 -display gtk,gl=on,zoom-to-fit=on -serial stdio
if errorlevel 1 (
    echo.
    echo [NOTE] OpenGL initialization failed. Launching fallback display...
    "%QEMU_CMD%" -bios "%~dp0bios.bin" -drive file="%~dp0cybfs_nvram.img",format=raw,if=ide -audiodev dsound,id=snd0,latency=20000 -machine pc,pcspk-audiodev=snd0 -device sb16,audiodev=snd0 -display gtk,zoom-to-fit=on -serial stdio
)
if errorlevel 1 (
    "%QEMU_CMD%" -bios "%~dp0bios.bin" -drive file="%~dp0cybfs_nvram.img",format=raw,if=ide -audiodev dsound,id=snd0 -device sb16,audiodev=snd0 -serial stdio
)
pause

# Cybforge Retro BIOS & Snake v2.1

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-x86%2016--bit%20Real%20Mode-lightgrey.svg)](#)
[![Format](https://img.shields.io/badge/ROM-64KB%20Binary-green.svg)](#)
[![Emulator](https://img.shields.io/badge/Emulator-QEMU%20x86__64-orange.svg)](#)

A custom, bare-metal **x86 16-bit PC BIOS** that boots an authentic retro AMIBIOS-style POST diagnostic sequence, offers a full **Cybforge Retro BIOS Setup Utility**, and directly launches a playable, retro **Snake Game v2.1** in pure assembly.

![Cybforge Snake Gameplay](assets/screenshot_gameplay.png)

---

## Highlights & Features

### 1. Bare-Metal x86 System Bringup
* **Reset Vector:** Hardware reset entry point at `0xF000:0xFFF0` mapped to physical top-of-ROM (`0xFFFF0`).
* **Cache & MTRR Initialization:** CR0 Cache Disable/Enable sequence, Cache-as-RAM (CAR), and MTRR WB memory type setup.
* **8259 PIC & 8254 PIT:** Complete dual 8259 Interrupt Controller remapping and PIT channel 0/2 timing initialization.
* **8042 Keyboard Controller Setup:** Hardware translation enabled via 8042 Controller Command Byte (`0x60 -> 0x40`), standardizing keyboard input into clean PS/2 Scancode Set 1.
* **UART Serial Diagnostics:** COM1 (`0x3F8`) configured for 115,200 Baud, 8N1 debugging output.
* **VGA Register Bringup:** Pure hardware VGA programming through Sequencer (`0x3C4`), CRT Controller (`0x3D4`), Graphics Controller (`0x3CE`), Attribute Controller (`0x3C0`), and DAC Palette (`0x3C8`).

### 2. Cybforge POST Screen
* **Authentic AMIBIOS POST Aesthetic:** Clean diagnostic text mode display with CPU, Co-Processor, Memory, Video, Keyboard, and Drive statistics.
* **Custom Cybforge Hexagonal Logo:** High-resolution 60-tile custom font loaded directly into VGA Plane 2 font memory (`0x80..0xBB`) and rendered on the right side of the screen in bright cyan.
* **Adaptive Screen Detection:** Automatic display resolution detection with zero CPU overhead using GPU-accelerated OpenGL scaling (`gtk,gl=on,zoom-to-fit=on`).
* **Interactive Boot Timing:** 3-second auto-boot countdown directly into Snake, with immediate start on `[ENTER]` or Setup entry on `[F12]` / `[DEL]`.

### 3. Cybforge Retro BIOS Setup Utility
* Classic blue AMIBIOS-style Setup interface accessed via `[F12]` or `[DEL]`.
* **Configurable Game & Hardware Parameters:**
  * **Game Speed:** `< Normal (120ms) >`, `< Fast (80ms) >`, `< Slow (160ms) >`
  * **Wall Collision:** `< Solid (Crash) >` (classic die on wall) or `< Wrap-Around >` (teleport across screen)
  * **PC Speaker Sound:** `< Enabled >` or `< Disabled >`
  * **Snake Face Style:** `< Classic Smile >` (glyph `0x07`) or `< Cool Shades >` (glyph `0x0A`)
  * **Starting Length:** `< 4 Segments >`, `< 3 Segments >`, `< 6 Segments >`
  * **Victory Target:** `< Full Board (1044) >` *(complete field takeover)*, `< 25 Apples >`, `< 50 Apples >`, `< 100 Apples >`
  * **Reset Defaults & Save & Boot:** Factory reset or instant boot to game.

### 4. The Snake Game (Version 2.1 Overhaul)
* **True 16-Scanline Pixel-Art Glyphs (Plane 2 Direct Loading):**
  * **Double Neon Cyan Border:** High-precision connecting corners and double lines (`0x01`..`0x06`).
  * **Cute Smiling Snake Head:** Expressive eyes and cheeks (`0x07`).
  * **Cyberpunk Sunglasses Head:** Angular shades with white specular glare (`0x0A`).
  * **Glossy 3D Apple:** Realistic curved leaf, wooden stem, and spherical 3D specular shine (`0x08`).
  * **Dragon Scale Body Segments:** Seamlessly interlocking scales with zero vertical/horizontal gaps (`0x09`).
* **Centered Modal Dialogs:**
  * **Start Window:** Centered double-box with `Press [ENTER] to Start`.
  * **Game Over Window:** Centered red modal box showing `Final Score: XXX` and action prompts, clearing background text to eliminate visual overlap.
* **Harmonic, Glitch-Free Audio Engine:**
  * Uses non-destructive PIT Channel 2 updates (`set_tone_freq`) to eliminate clicks and popping.
  * Musical intervals: Warm G5->C6 pickup chime, melancholic C5->Ab4->G4->Eb4 Game Over descent, upbeat E5->A5 launch sound, and triumphant 6-note Victory fanfare.
  * Low-latency DirectSound configuration (`-audiodev dsound,id=snd0,latency=20000`).
* **High Score Tracking:** Session `HIGH_SCORE` (`0x1A0E`) dynamically preserved and displayed on the HUD.
* **Safe Apple Spawning:** Guarantees apples never spawn on top of existing snake segments.
* **Fluid Controls & Shortcuts:** `[WASD]` and `[Arrow Keys]` with single-turn locking and instant `[ESC]` shortcut to BIOS Setup.

![Game Over Modal Screen](assets/screenshot_gameover.png)

---

## Controls

| Screen | Action | Key(s) |
| :--- | :--- | :--- |
| **POST Screen** | Enter BIOS Setup | `[F12]` or `[DEL]` |
| **POST Screen** | Boot Snake Immediately | `[ENTER]` |
| **BIOS Setup** | Navigate Items | `[W]` / `[S]` or `[Up]` / `[Down]` |
| **BIOS Setup** | Change Setting / Value | `[A]` / `[D]` or `[Left]` / `[Right]` or `[ENTER]` / `[SPACE]` |
| **BIOS Setup** | Save & Boot Game | `[ESC]` |
| **Snake Game** | Steer Snake | `[W]` `[A]` `[S]` `[D]` or `[Arrow Keys]` |
| **Snake Game** | Start / Restart Game | `[ENTER]` |
| **Snake Game** | Pause & Open BIOS Setup | `[ESC]` |
| **Victory Screen**| Play Again / Return to Setup | `[ENTER]` to Restart, `[ESC]` for BIOS Setup |

---

## Memory Map (Real Mode, DS = 0x0000)

| Address Range | Size | Description |
| :--- | :--- | :--- |
| `0x1000 - 0x14AF` | 1,200 Bytes | `SNAKE_X` Coordinate ring buffer (supports full 1044-tile field) |
| `0x1500 - 0x19AF` | 1,200 Bytes | `SNAKE_Y` Coordinate ring buffer |
| `0x1A00` | 2 Bytes | `SNAKE_LEN` Current snake length |
| `0x1A02` | 1 Byte | `SNAKE_DIR` Current movement direction (0=Up, 1=Right, 2=Down, 3=Left) |
| `0x1A03` | 1 Byte | `NEXT_DIR` Buffered turn direction |
| `0x1A04 - 0x1A05` | 2 Bytes | `FOOD_X`, `FOOD_Y` Active apple coordinates |
| `0x1A06` | 2 Bytes | `SCORE` Current score (BCD displayed) |
| `0x1A08` | 2 Bytes | `RND_SEED` Linear Congruential Generator seed |
| `0x1A0A` | 1 Byte | `DIR_LOCKED` Single-turn lock flag |
| `0x1A0E` | 2 Bytes | `HIGH_SCORE` Persistent session high score |
| `0x1A10 - 0x1A17` | 8 Bytes | BIOS Setup configuration bytes (`CFG_SPEED`, `CFG_WALLS`, `CFG_WIN`, etc.) |
| `0xB800:0x0000` | 4,000 Bytes | VGA Color Text Buffer (80x25 character & attribute pairs) |
| `0xA000:0x0000` | Plane 2 | VGA Font Memory (Custom 16-scanline glyphs) |

---

## Building and Running

### Prerequisites
* [NASM](https://www.nasm.us/) (Netwide Assembler)
* [QEMU](https://www.qemu.org/) (`qemu-system-x86_64`)
* Python 3 with `Pillow` and `numpy` (for `gen_bios.py`)

### 1. Launch with One Click
Double-click:
```cmd
run.bat
```
`run.bat` automatically checks screen resolution, builds `bios.bin` if missing, and launches QEMU with hardware OpenGL scaling and low-latency DirectSound audio:
```cmd
qemu-system-x86_64 -bios bios.bin -audiodev dsound,id=snd0,latency=20000 -machine pc,pcspk-audiodev=snd0 -display gtk,gl=on,zoom-to-fit=on
```

### 2. Manual Build
To re-generate `bios.asm` and compile `bios.bin`:
```cmd
build.bat
```
Or manually:
```cmd
python gen_bios.py
nasm -f bin bios.asm -o bios.bin
```

---

## License

This project is licensed under the [MIT License](LICENSE) - see the LICENSE file for details.

Copyright (c) 2026 Cybforge.

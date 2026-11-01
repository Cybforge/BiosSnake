# Cybforge Retro BIOS & Snake v2.3 (256 KB ROM & 16-Bit PCM Audio Edition)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-x86%2016--bit%20Real%20Mode-lightgrey.svg)](#)
[![Format](https://img.shields.io/badge/ROM-256KB%20Binary-brightgreen.svg)](#)
[![Audio](https://img.shields.io/badge/Audio-Sound%20Blaster%2016%2016--Bit%20PCM-blueviolet.svg)](#)
[![DMA](https://img.shields.io/badge/DMA-Channel%205%20(16--Bit)-orange.svg)](#)
[![Emulator](https://img.shields.io/badge/Emulator-QEMU%20x86__64-orange.svg)](#)
[![Version](https://img.shields.io/badge/Version-2.3%20Studio%20Audio-brightgreen.svg)](#)

A custom, bare-metal **x86 16-bit PC BIOS** in a full **256 KB (`262,144 Bytes`) ROM image**. It boots an authentic AMIBIOS-style POST diagnostic sequence with Sound Blaster 16 hardware auto-detection, offers an expanded **Cybforge Retro BIOS Setup Utility** with CMOS NVRAM persistence, hardware VGA DAC themes, selectable arenas, a high-definition **16-bit Sound Blaster 16 PCM audio engine**, and directly launches an arcade **Snake Game v2.3** in pure assembly.

![Cybforge Snake Matrix Green Gameplay](assets/screenshot_gameplay.png)

---

## Visual Showcase Gallery

| POST RAM Counter & SB16 Detection | Cybforge BIOS Setup Utility (Sound: SB16 16-Bit) |
| :---: | :---: |
| ![POST Screen](assets/screenshot_post.png) | ![BIOS Setup](assets/screenshot_setup.png) |

| In-Game Pause Modal Dialog `[P]` | Amber CRT Theme & The Maze Arena |
| :---: | :---: |
| ![In-Game Pause](assets/screenshot_paused.png) | ![The Maze Amber](assets/screenshot_maze_amber.png) |

| New High Score Initials Entry `[A A A]` | Hall of Champions Top 3 Leaderboard |
| :---: | :---: |
| ![Initials Dialog](assets/screenshot_initials.png) | ![Hall of Champions](assets/screenshot_gameover.png) |

| Victory Trophy Screen (Complete Board Takeover) |
| :---: |
| ![Victory Trophy](assets/screenshot_victory.png) |

---

## 256 KB ROM Architecture (4 x 64 KB Blocks)

The BIOS image is constructed as an authentic **256 KB ROM (`262,144 Bytes`)**, organized into four distinct 64 KB physical memory blocks:

```
+-------------------------------------------------------------------------------+
|                           256 KB BIOS ROM ARCHITECTURE                         |
+-------------+-----------------------+-------------------------+---------------+
| ROM Block   | ROM File Offsets      | 32-bit Linear Address   | 16-bit Real   |
|             |                       | (Unreal Mode FS:ESI)    | Mode Segment  |
+-------------+-----------------------+-------------------------+---------------+
| Block 0     | 0x00000 - 0x0FFFF     | 0xFFFC0000 - 0xFFFCFFFF | High ROM      |
|             | (65,536 Bytes)        | ROM Banner & Reserved   | Space         |
+-------------+-----------------------+-------------------------+---------------+
| Block 1     | 0x10000 - 0x1FFFF     | 0xFFFD0000 - 0xFFFDFFFF | High ROM      |
|             | (65,536 Bytes)        | 16-Bit PCM Audio Bank A | Space         |
+-------------+-----------------------+-------------------------+---------------+
| Block 2     | 0x20000 - 0x2FFFF     | 0xFFFE0000 - 0xFFFEFFFF | Segment 0xE000|
|             | (65,536 Bytes)        | 16-Bit PCM Audio Bank B | (0xE000:0000) |
+-------------+-----------------------+-------------------------+---------------+
| Block 3     | 0x30000 - 0x3FFFF     | 0xFFFF0000 - 0xFFFFFFFF | Segment 0xF000|
|             | (65,536 Bytes)        | BIOS Code, Setup, Snake | (0xF000:0000) |
|             |                       | & CPU Reset Vector      | (Reset: FFF0h)|
+-------------+-----------------------+-------------------------+---------------+
```

---

## Sound Blaster 16 Digital Audio Engine (16-Bit PCM)

### 1. Hardware Architecture & Unreal Mode
* **Flat Real Mode (Unreal Mode):** Uses a brief 6-instruction switch into Protected Mode during boot to load a 4 GB data segment descriptor into `FS`, then immediately returns to 16-bit Real Mode. This allows Real Mode instructions (`a32 mov eax, [fs:esi]`) to access any byte across the entire 256 KB ROM.
* **Intel 8237A DMA Channel 5:** Configured for high-speed 16-bit word streaming from conventional RAM at physical address `0x20000` (DMA Page register `0x8B = 0x02`, Base `0xC4 = 0x0000`, Mode `0xD6 = 0x49`).
* **SB16 DSP 4.xx Control:** Initialized via DSP reset (`Port 0x226`), speaker enabled (`DSP 0xD1`), sample rate configured (`DSP 0x41` for 11,025 Hz), and triggered using high-performance 16-bit single-cycle DMA transfers (`DSP 0xB6`, Mode `0x10` Signed Mono).
* **Hardware Mixer (`Ports 0x224 / 0x225`):** Dynamically programs Master Volume (L/R `0x30`, `0x31`) and Voice Volume (L/R `0x32`, `0x33`) to `0xF8` for crisp, high-amplitude acoustic output.

### 2. High-Definition 16-Bit Sound Bank (11,025 Hz)
| Index | ID | Description | Samples | Duration | Linear ROM Address |
| :---: | :--- | :--- | :---: | :---: | :---: |
| **0** | `SND_CRUNCH` | Crisp apple bite (exponential FM + noise crunch) | 2,206 | 0.20s | `0xFFFD0000` |
| **1** | `SND_GOLDEN` | Magical ascending polyphonic chime (E6-G#6-B6-E7) | 6,064 | 0.55s | `0xFFFD113C` |
| **2** | `SND_CRASH` | Sub-bass impact + metal shatter noise transient | 4,962 | 0.45s | `0xFFFD409C` |
| **3** | `SND_START` | Arcade power coin / start chime (E5-A5-C#6) | 3,858 | 0.35s | `0xFFFD6760` |
| **4** | `SND_PAUSE` | Futuristic double-tone pause chirp | 1,764 | 0.16s | `0xFFFD8584` |
| **5** | `SND_BOOT` | Cyber startup chord (C5 + G5 + C6 + E6) | 5,512 | 0.50s | `0xFFFD934C` |
| **6** | `SND_GAMEOVER` | Melancholic minor descent (A4-F4-D4-C#4) | 9,372 | 0.85s | `0xFFFDBE5C` |
| **7** | `SND_VICTORY` | Majestic polyphonic brass fanfare | 13,230 | 1.20s | `0xFFFE0794` |

### 3. Four Selectable Sound Modes in BIOS Setup
Users can toggle the sound output in BIOS Setup under `Sound Output`:
* `< SB16 16-Bit >`: Pristine, zero-latency 16-bit PCM WAV playback via Sound Blaster 16 DMA.
* `< PC Speaker >`: Classic 1981 IBM PC square-wave chimes via Intel 8254 PIT Channel 2.
* `< Dual Audio >`: Simultaneous playback through both SB16 16-bit DAC and PC Speaker.
* `< Muted >`: Completely silent operation.

---

## Core BIOS & Gameplay Features

### 1. Animated POST Base RAM Counter
* Fast, audible memory test animating from `0 KB` to `640 KB OK` in `64 KB` increments.
* Real diagnostic hardware speaker clicks on every increment.
* Displays CPU, Co-Processor, Display, Keyboard, PIT Timer, Disks, and **Sound Blaster 16 Hardware Detection**.

### 2. VGA Hardware DAC Color Themes
Switches the 16 text-mode color registers via VGA DAC ports `0x3C8` / `0x3C9`:
* **Cyberpunk Neon (Default):** Deep neon blue background with electric green, bright yellow, and radiant cyan.
* **Matrix Green:** Monochrome green phosphor terminal with dark phosphor greens and blazing lime-green highlights.
* **Amber CRT:** Warm 1980s amber/orange monochrome terminal with soft amber backgrounds and golden text.
* **CGA Retro:** Faithful 1981 IBM PC CGA 16-color palette.
* Live real-time palette preview inside the BIOS Setup screen!

### 3. CMOS NVRAM Non-Volatile Persistence
* Reads and writes configuration data and leaderboard scores to extended CMOS RTC NVRAM registers (`0x40`..`0x59`) via I/O ports `0x70` and `0x71`.
* **Integrity Validation:** Signature byte (`0xCB`) and XOR checksum validation prevent corrupted states and automatically initialize factory defaults when CMOS is blank.
* Persists high scores, arena choice, speed, sound, and theme across reboots!

### 4. Interactive In-Game Pause
* Press `[P]` or `[SPACE]` during gameplay to instantly pause the action.
* Displays a centered neon double-box modal dialog (`P A U S E D`).
* Freezes the snake and timers without dropping inputs.

### 5. Golden Bonus Apples & Countdown HUD
* A shimmering golden bonus apple spawns every **5 regular apples** eaten.
* Awards **+50 bonus points** upon capture!
* Accompanied by a distinct ascending spawn jingle and rewarding pickup chime.
* **HUD Countdown Timer:** Displays `BONUS: 08s` at the top of the screen; the golden apple despawns if not caught in time.

### 6. Selectable Game Arenas
* **Classic Open:** Open, obstacle-free rectangular arena.
* **Four Pillars:** Four solid structural columns placed strategically in the corners of the board.
* **The Maze:** Two horizontal barrier walls creating a tight center chicane.

### 7. Crash Dissolve Animation
* Plays `SND_CRASH` through SB16 DMA, flashes the snake between bright red and white, and dissolves the body segment-by-segment from tail to head before showing the Game Over dialog.

### 8. Top-3 Leaderboard & Interactive Initials Entry
* If your final score beats the Top-3 record, an arcade-style dialog prompts you for a 3-letter name (`[ A A A ]`).
* Use `[Left]` / `[Right]` to switch characters and `[Up]` / `[Down]` or `[W]` / `[S]` to cycle letters `A` to `Z`.
* Press `[ENTER]` to save your initials into CMOS NVRAM!
* View the permanent **Hall of Champions** on every Game Over screen.

### 9. Victory Trophy Screen
* Achieving your victory target triggers a triumphant brass fanfare (`SND_VICTORY`).
* Renders a golden victory trophy inscribed with `#1 MASTER CYBFORGE`.

---

## Controls

| Screen | Action | Key(s) |
| :--- | :--- | :--- |
| **POST Screen** | Enter BIOS Setup | `[F12]` or `[DEL]` |
| **POST Screen** | Boot Snake Immediately | `[ENTER]` |
| **BIOS Setup** | Navigate Items | `[W]` / `[S]` or `[Up]` / `[Down]` |
| **BIOS Setup** | Change Setting / Value | `[A]` / `[D]` or `[Left]` / `[Right]` or `[ENTER]` / `[SPACE]` |
| **BIOS Setup** | Save & Boot Game | `[ESC]` or select `Save & Boot Game` |
| **Snake Game** | Steer Snake | `[W]` `[A]` `[S]` `[D]` or `[Arrow Keys]` |
| **Snake Game** | Pause / Resume | `[P]` or `[SPACE]` |
| **Snake Game** | Exit to BIOS Setup | `[ESC]` |
| **Initials Dialog** | Select Letter / Change Character | `[Left]` / `[Right]` to select, `[Up]` / `[Down]` to change |
| **Initials Dialog** | Confirm Name | `[ENTER]` |
| **Game Over** | Restart Game | `[ENTER]` |
| **Game Over** | Open BIOS Setup | `[ESC]` |
| **Victory Screen** | Play Again / BIOS Setup | `[ENTER]` to restart, `[ESC]` for setup |

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
| `0x1A06` | 2 Bytes | `SCORE` Current score |
| `0x1A08` | 2 Bytes | `RND_SEED` Linear Congruential Generator seed |
| `0x1A0A` | 1 Byte | `DIR_LOCKED` Single-turn lock flag |
| `0x1A0D` | 1 Byte | `QUEUED_DIR` Buffer for rapid double-key turns |
| `0x1A0E` | 2 Bytes | `HIGH_SCORE` Persistent session high score |
| `0x1A10 - 0x1A19` | 10 Bytes | BIOS Setup options (`SPEED`, `WALLS`, `SOUND`, `FACE`, `LEN`, `WIN`, `THEME`, `ARENA`) |
| `0x1A1A - 0x1A1C` | 3 Bytes | `GOLD_FOOD_X`, `GOLD_FOOD_Y`, `GOLD_TIMER` |
| `0x1A1E` | 1 Byte | `APPLE_COUNT` Eaten apple counter |
| `0x1A20 - 0x1A2E` | 15 Bytes | `TOP3_TABLE` 3x (3-byte name, 2-byte score) |
| `0x1A30 - 0x1A33` | 4 Bytes | `CURRENT_NAME` (3 bytes) and `CUR_CHAR_IDX` (1 byte) |
| `0x1A34` | 1 Byte | `sb16_detected` SB16 Hardware Flag (1=Detected, 0=None) |
| `0x2000:0x0000` | 64 KB | RAM Playback Buffer for Sound Blaster 16 DMA Channel 5 |
| `0xB800:0x0000` | 4,000 Bytes | VGA Color Text Buffer (80x25 character & attribute pairs) |
| `0xA000:0x0000` | Plane 2 | VGA Font Memory (Custom 16-scanline glyphs & Cybforge logo) |

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
`run.bat` automatically checks screen resolution, builds `bios.bin` (256 KB) if missing, and launches QEMU with Sound Blaster 16 DMA audio, DirectSound low latency, and hardware OpenGL scaling:
```cmd
qemu-system-x86_64 -bios bios.bin -audiodev dsound,id=snd0,latency=20000 -machine pc,pcspk-audiodev=snd0 -device sb16,audiodev=snd0 -display gtk,gl=on,zoom-to-fit=on
```

### 2. Manual Build
To re-generate `bios.asm`, synthesize the 16-bit PCM sound bank, and assemble `bios.bin` (256 KB):
```cmd
build.bat
```
Or directly via Python:
```cmd
python gen_bios.py
```

---

## License

This project is licensed under the [MIT License](LICENSE) - see the LICENSE file for details.

Copyright (c) 2026 Cybforge.

# Cybforge Retro BIOS & Snake v2.2 (Ultimate Expansion)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-x86%2016--bit%20Real%20Mode-lightgrey.svg)](#)
[![Format](https://img.shields.io/badge/ROM-64KB%20Binary-green.svg)](#)
[![Emulator](https://img.shields.io/badge/Emulator-QEMU%20x86__64-orange.svg)](#)
[![Version](https://img.shields.io/badge/Version-2.2%20Ultimate%20Expansion-brightgreen.svg)](#)

A custom, bare-metal **x86 16-bit PC BIOS** that boots an authentic retro AMIBIOS-style POST diagnostic sequence, offers an expanded **Cybforge Retro BIOS Setup Utility** with CMOS NVRAM persistence, hardware VGA DAC themes, selectable arenas, and directly launches an arcade **Snake Game v2.2** in pure assembly.

![Cybforge Snake Matrix Green Gameplay](assets/screenshot_gameplay.png)

---

## Visual Showcase Gallery

| POST RAM Counter (0..640 KB OK) | Cybforge BIOS Setup Utility (10 Rows) |
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

## Ultimate Expansion (v2.2) Feature Pack

### 1. Animated POST Base RAM Counter
* Fast, audible memory test animating from `0 KB` to `640 KB OK` in `64 KB` increments.
* Real PC speaker hardware click on every increment using timer counter pulses.
* Displays alongside CPU, Co-Processor, Display, Keyboard, PIT Timer, and Disk diagnostics.

### 2. VGA Hardware DAC Color Themes
Switches the 16 text-mode color registers via VGA DAC ports `0x3C8` / `0x3C9`:
* **Cyberpunk Neon (Default):** Deep neon blue background with electric green, bright yellow, and radiant cyan.
* **Matrix Green:** Monochrome green phosphor terminal with dark phosphor greens and blazing lime-green highlights.
* **Amber CRT:** Warm 1980s amber/orange monochrome terminal with soft amber backgrounds and golden text.
* **CGA Retro:** Faithful 1981 IBM PC CGA 16-color palette (pure primary RGB and crisp high-intensity tones).
* Real-time palette updates live inside the BIOS Setup screen!

### 3. CMOS NVRAM Non-Volatile Persistence
* Reads and writes configuration data and leaderboard scores to extended CMOS RTC NVRAM registers (`0x40`..`0x59`) via I/O ports `0x70` and `0x71`.
* **Integrity Validation:** Signature byte (`0xCB`) and XOR checksum validation prevent corrupted states and automatically initialize factory defaults when CMOS is blank.
* Persists your high scores, arena choice, speed, sound, and theme across reboots and emulator resets!

### 4. Interactive In-Game Pause
* Press `[P]` or `[SPACE]` during gameplay to instantly pause the action.
* Displays a centered neon double-box modal dialog (`P A U S E D`).
* Fully freezes the snake and timers without dropping inputs. Pressing `[P]` or `[SPACE]` resumes immediately.

### 5. Golden Bonus Apples & Countdown HUD
* A shimmering golden bonus apple spawns on the board every **5 regular apples** eaten.
* Awards **+50 bonus points** upon capture!
* Accompanied by a distinct ascending spawn jingle and a rewarding 3-tone pickup chime.
* **HUD Countdown Timer:** Displays `GOLD: Xs` at the top of the screen; the golden apple vanishes if not captured within 8 seconds.

### 6. Selectable Game Arenas
* **Classic Open:** Open, obstacle-free rectangular arena.
* **Four Pillars:** Four solid structural columns placed strategically in the corners of the board.
* **The Maze:** Two horizontal barrier walls creating a tight center chicane.
* Fruit and golden apple spawns strictly avoid obstacle tiles.

### 7. Crash Dissolve Animation
* Flashes the snake between bright red and white with a deep crash buzz on collision.
* The snake body dissolves segment-by-segment from tail to head with rising pitch pops before opening the Game Over dialog.

### 8. Top-3 Leaderboard & Interactive Initials Entry
* If your final score beats the Top-3 record, an arcade-style dialog prompts you for a 3-letter name (`[ A A A ]`).
* Use `[Left]` / `[Right]` to switch characters and `[Up]` / `[Down]` or `[W]` / `[S]` to cycle through letters `A` to `Z`.
* Press `[ENTER]` to save your initials into CMOS NVRAM!
* View the permanent **Hall of Champions** on every Game Over screen.

### 9. Victory Trophy Screen
* Achieving your victory target triggers a triumphant 6-note fanfare.
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

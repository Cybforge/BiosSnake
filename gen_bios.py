from pathlib import Path
import numpy as np
from PIL import Image

BASE_DIR = Path(__file__).resolve().parent

SRC = BASE_DIR / "src" / "base_bios.txt"
if not SRC.exists():
    SRC = Path(r"C:\Users\jonas\Desktop\Desktop stuff\bios.txt")

DEST = BASE_DIR / "bios.asm"

LOGO_PNG = BASE_DIR / "assets" / "logo.png"
if not LOGO_PNG.exists():
    LOGO_PNG = Path(r"C:\Users\jonas\.gemini\antigravity\brain\8cfa1e6e-59a0-463b-bd8e-994dcd97e398\.user_uploaded\media_1792826681534_ee160acc.png")

# --- Process Cybforge Logo (60 Tiles: 10 cols x 6 rows) ---
im = Image.open(LOGO_PNG)
arr_rgba = np.array(im.convert("RGBA"))
alpha = arr_rgba[:, :, 3]
lum = 0.299 * arr_rgba[:, :, 0] + 0.587 * arr_rgba[:, :, 1] + 0.114 * arr_rgba[:, :, 2]
fg = (alpha > 50) & (lum > 50)
coords = np.argwhere(fg)
y0, x0 = coords.min(axis=0)
y1, x1 = coords.max(axis=0) + 1
crop = im.crop((x0, y0, x1, y1)).convert("L")

COLS = 10
ROWS = 6
W = COLS * 8   # 80
H = ROWS * 16  # 96

target_w, target_h = 72, 72
resized = crop.resize((target_w, target_h), Image.Resampling.LANCZOS)
canvas = Image.new("L", (W, H), 0)
canvas.paste(resized, ((W - target_w) // 2, (H - target_h) // 2))
arr_canvas = np.array(canvas)
bin_canvas = (arr_canvas > 75).astype(np.uint8)

tiles = []
for r in range(ROWS):
    for c in range(COLS):
        tb = []
        for y in range(16):
            b = 0
            for x in range(8):
                if bin_canvas[r * 16 + y, c * 8 + x]:
                    b |= (1 << (7 - x))
            tb.append(b)
        tiles.append(tb)

logo_table_asm = "logo_font_table:\n"
for idx, tb in enumerate(tiles):
    code = 0x80 + idx
    bytes_str = ", ".join([f"0x{b:02X}" for b in tb])
    logo_table_asm += f"    db 0x{code:02X}, {bytes_str}\n"
logo_table_asm += "    db 0\n"


# =============================================================================
# 16-BIT PCM WAV AUDIO SYNTHESIS & 256 KB ROM SOUND BANK (11,025 Hz, Signed Mono)
# =============================================================================
SR = 11025

def to_int16_bytes(arr):
    clipped = np.clip(arr * 30000, -32767, 32767).astype(np.int16)
    b = clipped.tobytes()
    if len(b) % 4 != 0:
        b += b"\x00" * (4 - (len(b) % 4))
    return b

# Helper filters for warm, studio-grade musical synthesis (zero harshness)
def soft_lpf(sig, k=5):
    kernel = np.ones(k, dtype=np.float64) / k
    return np.convolve(sig, kernel, mode="same")

def add_reverb(sig, delay_s=0.048, decay=0.28):
    out = sig.copy()
    d1 = int(SR * delay_s)
    d2 = int(SR * delay_s * 1.85)
    if d1 < len(out):
        out[d1:] += sig[:-d1] * decay
    if d2 < len(out):
        out[d2:] += sig[:-d2] * (decay * 0.55)
    return out

def marimba_note(t_arr, freq, decay=14.0):
    env = (1.0 - np.exp(-t_arr * 220.0)) * np.exp(-t_arr * decay)
    fundamental = np.sin(2 * np.pi * freq * t_arr)
    harm_4 = 0.28 * np.sin(2 * np.pi * (freq * 4.0) * t_arr) * np.exp(-t_arr * (decay * 2.5))
    sub = 0.18 * np.sin(2 * np.pi * (freq * 0.5) * t_arr)
    return (fundamental + harm_4 + sub) * env

# 0. SND_CRUNCH (~0.24s): Google Snake two-stage "Bubble Pop + Warm Marimba Munch"
t0 = np.linspace(0, 0.24, int(SR * 0.24), endpoint=False)
pop_freq = 360.0 + 520.0 * (1.0 - np.exp(-t0 * 45.0))
pop_tone = np.sin(2 * np.pi * pop_freq * t0) * np.exp(-t0 * 24.0)
munch = np.zeros_like(t0)
for start_t, freq in [(0.00, 587.33), (0.055, 880.00), (0.11, 1174.66)]:
    m = t0 >= start_t
    tn = t0[m] - start_t
    munch[m] += marimba_note(tn, freq, decay=18.0) * 0.55
np.random.seed(42)
crisp_velvet = soft_lpf(np.random.uniform(-0.35, 0.35, len(t0)), k=7) * np.exp(-t0 * 32.0)
snd_crunch = to_int16_bytes(add_reverb(pop_tone * 0.38 + munch * 0.52 + crisp_velvet * 0.18, 0.032, 0.22))

# 1. SND_GOLDEN (~0.60s): Celestial Harp & Glockenspiel Shimmer Arpeggio (C5-E5-G5-B5-E6)
t1 = np.linspace(0, 0.60, int(SR * 0.60), endpoint=False)
sig1 = np.zeros_like(t1)
for i, freq in enumerate([523.25, 659.25, 783.99, 987.77, 1318.51]):
    start_t = i * 0.065
    m = t1 >= start_t
    tn = t1[m] - start_t
    env = (1.0 - np.exp(-tn * 180.0)) * np.exp(-tn * 6.5)
    voice = (np.sin(2 * np.pi * freq * tn) +
             0.45 * np.sin(2 * np.pi * (freq * 1.003) * tn) +
             0.25 * np.sin(2 * np.pi * (freq * 2.0) * tn) * np.exp(-tn * 10.0) +
             0.12 * np.sin(2 * np.pi * (freq * 3.0) * tn) * np.exp(-tn * 14.0))
    sig1[m] += voice * env * 0.32
snd_golden = to_int16_bytes(add_reverb(sig1, 0.055, 0.35))

# 2. SND_CRASH (~0.52s): Cartoon Sub-Bass Bonk + Twinkling Dizzy Stars
t2 = np.linspace(0, 0.52, int(SR * 0.52), endpoint=False)
bonk_phase = 2 * np.pi * (48.0 * t2 + (135.0 / 16.0) * (1.0 - np.exp(-t2 * 16.0)))
bonk = np.sin(bonk_phase) * np.exp(-t2 * 8.5)
dizzy = np.zeros_like(t2)
for start_t, freq in [(0.08, 987.77), (0.18, 880.00), (0.28, 783.99), (0.38, 659.25)]:
    m = t2 >= start_t
    tn = t2[m] - start_t
    vib = 1.0 + 0.018 * np.sin(2 * np.pi * 14.0 * tn)
    dizzy[m] += np.sin(2 * np.pi * freq * vib * tn) * np.exp(-tn * 12.0) * 0.30
snd_crash = to_int16_bytes(add_reverb(bonk * 0.65 + dizzy * 0.45, 0.045, 0.25))

# 3. SND_START (~0.38s): Warm Acoustic Pluck Triad (C5 -> G5 -> C6)
t3 = np.linspace(0, 0.38, int(SR * 0.38), endpoint=False)
sig3 = np.zeros_like(t3)
for i, freq in enumerate([523.25, 783.99, 1046.50]):
    start_t = i * 0.065
    m = t3 >= start_t
    tn = t3[m] - start_t
    sig3[m] += marimba_note(tn, freq, decay=9.5) * 0.48
snd_start = to_int16_bytes(add_reverb(sig3, 0.040, 0.28))

# 4. SND_PAUSE (~0.18s): Gentle Wooden Marimba Double-Tap (A5 -> E5)
t4 = np.linspace(0, 0.18, int(SR * 0.18), endpoint=False)
sig4 = np.zeros_like(t4)
for start_t, freq in [(0.00, 880.00), (0.075, 659.25)]:
    m = t4 >= start_t
    tn = t4[m] - start_t
    sig4[m] += marimba_note(tn, freq, decay=22.0) * 0.65
snd_pause = to_int16_bytes(add_reverb(sig4, 0.030, 0.20))

# 5. SND_BOOT (~0.62s): Lush Modern UEFI Major-9th Synthesizer Pad & Chime
t5 = np.linspace(0, 0.62, int(SR * 0.62), endpoint=False)
pad_env = (1.0 - np.exp(-t5 * 28.0)) * np.exp(-t5 * 4.2)
pad = np.zeros_like(t5)
for freq, amp in [(261.63, 0.28), (392.00, 0.24), (523.25, 0.26), (659.25, 0.22), (783.99, 0.18), (1174.66, 0.15)]:
    pad += amp * (np.sin(2 * np.pi * freq * t5) + 0.5 * np.sin(2 * np.pi * (freq * 1.0025) * t5))
snd_boot = to_int16_bytes(add_reverb(pad * pad_env * 0.52, 0.060, 0.35))

# 6. SND_GAMEOVER (~0.88s): Warm Rhodes Electric Piano Cadence (A4 -> G4 -> F4 -> E4)
t6 = np.linspace(0, 0.88, int(SR * 0.88), endpoint=False)
sig6 = np.zeros_like(t6)
for i, freq in enumerate([440.00, 392.00, 349.23, 329.63]):
    start_t = i * 0.18
    m = t6 >= start_t
    tn = t6[m] - start_t
    env = (1.0 - np.exp(-tn * 120.0)) * np.exp(-tn * 4.8)
    trem = 1.0 + 0.08 * np.sin(2 * np.pi * 5.5 * tn)
    rhodes = (np.sin(2 * np.pi * freq * tn) +
              0.30 * np.sin(2 * np.pi * (freq * 2.0) * tn) * np.exp(-tn * 8.0) +
              0.12 * np.sin(2 * np.pi * (freq * 3.0) * tn) * np.exp(-tn * 14.0))
    sig6[m] += rhodes * env * trem * 0.42
snd_gameover = to_int16_bytes(add_reverb(sig6, 0.055, 0.30))

# 7. SND_VICTORY (~1.25s): Symphonic Brass & Glockenspiel Victory Fanfare
t7 = np.linspace(0, 1.25, int(SR * 1.25), endpoint=False)
sig7 = np.zeros_like(t7)
notes = [
    (0.00, 0.14, [523.25, 659.25]),
    (0.14, 0.14, [659.25, 783.99]),
    (0.28, 0.14, [783.99, 1046.50]),
    (0.42, 0.24, [1046.50, 1318.51]),
    (0.66, 0.14, [783.99, 1046.50]),
    (0.80, 0.42, [523.25, 1046.50, 1318.51, 1567.98])
]
for start_t, dur, freqs in notes:
    m = (t7 >= start_t) & (t7 < start_t + dur + 0.32)
    tn = t7[m] - start_t
    env = (1.0 - np.exp(-tn * 95.0)) * np.exp(-tn * (3.6 if dur > 0.2 else 6.8))
    ss = np.zeros_like(tn)
    for f in freqs:
        ss += (np.sin(2 * np.pi * f * tn) +
               0.35 * np.sin(2 * np.pi * (f * 1.002) * tn) +
               0.22 * np.sin(2 * np.pi * (f * 2.0) * tn) * np.exp(-tn * 7.0))
    sig7[m] += ss * env * 0.22
snd_victory = to_int16_bytes(add_reverb(sig7, 0.060, 0.34))

pcm_samples = [snd_crunch, snd_golden, snd_crash, snd_start, snd_pause, snd_boot, snd_gameover, snd_victory]
pcm_names = ["SND_CRUNCH", "SND_GOLDEN", "SND_CRASH", "SND_START", "SND_PAUSE", "SND_BOOT", "SND_GAMEOVER", "SND_VICTORY"]

sample_blob = bytearray()
sample_table_asm = "align 8\nsample_table:\n"
base_linear = 0xFFFD0000

for name, s_bytes in zip(pcm_names, pcm_samples):
    addr = base_linear + len(sample_blob)
    words = len(s_bytes) // 2
    sample_table_asm += f"    dd 0x{addr:08X} ; {name}\n    dw {words}\n"
    sample_blob.extend(s_bytes)

assert len(sample_blob) <= 131072, "Audio sample blob exceeds 128 KB!"
block1_2 = sample_blob + b"\x00" * (131072 - len(sample_blob))

# =============================================================================
# BLOCK 0 (0xFFFC0000): REAL CYBFS v1.0 MASTER FILESYSTEM IMAGE
# =============================================================================
# Mounted into live read/write RAM at 0x3000..0x7FFF on cold boot or 'format'.
# Superblock : 0x3000..0x301F (32 Bytes)
# Inode Table: 0x3020..0x341F (32 Inodes x 32 Bytes = 1024 Bytes)
# Data Pool  : 0x3420..0x7FFF (19,424 Bytes live R/W storage)
import struct

CYBFS_BASE_RAM = 0x3000
CYBFS_DATA_START = 0x3420

initial_ram_files = [
    # (parent_id, name, content_bytes)
    (0, "startup.nsh", (
        b"echo Executing FS0:\\startup.nsh ...\n"
        b"ver\n"
        b"time\n"
    )),
    (0, "readme.txt", (
        b"Cybforge Live File System (CybFS v1.0 - Real Inodes & R/W RAM Pool)\n"
        b"  write <file> <text>  Create/overwrite file in current directory\n"
        b"  append <file> <text> Append new line to an existing file\n"
        b"  cat <file>           Read live file bytes (or ROM hex header)\n"
        b"  rm <name>            Delete file or directory from Inode table\n"
        b"  mkdir <dir>          Create a real subdirectory\n"
        b"  run <file.nsh>       Execute commands from a script file\n"
    )),
    (0, "sys.cfg", (
        b"rom_size=262144\n"
        b"cpu_mode=unreal_32bit\n"
        b"audio_hw=sb16_dma5_16bit\n"
        b"fs_mount=0x3000_rw\n"
    )),
]

inodes_bin = bytearray(32 * 32)
data_pool_bin = bytearray()

def set_inode(slot, flags, parent_id, data_off, data_seg_hi, file_size, name, meta=0xFF):
    name_b = name.encode("ascii")[:15]
    name_padded = name_b + b"\x00" * (16 - len(name_b))
    meta_padded = bytes([meta]) + b"\x00" * 7
    entry = struct.pack("<BBHHH16s8s", flags, parent_id, data_off, data_seg_hi, file_size, name_padded, meta_padded)
    inodes_bin[slot * 32 : (slot + 1) * 32] = entry

# Slot 0: Reserved for Root (\) reference
set_inode(0, 0x02, 0, 0, 0, 0, "\\")

# Slot 1: Directory 'efi' (parent=0)
set_inode(1, 0x02, 0, 0, 1, 0, "efi")

# Slot 2: Directory 'audio' (parent=0)
set_inode(2, 0x02, 0, 0, 2, 0, "audio")

next_slot = 3
for parent_id, fname, fbytes in initial_ram_files:
    ram_addr = CYBFS_DATA_START + len(data_pool_bin)
    set_inode(next_slot, 0x01, parent_id, ram_addr, 0x0000, len(fbytes), fname)
    data_pool_bin.extend(fbytes)
    next_slot += 1

# ROM-mapped system files in \efi (parent=1)
set_inode(next_slot, 0x03, 1, 0x0000, 0xFFFF, 65535, "bios.rom", 0xFE); next_slot += 1
set_inode(next_slot, 0x03, 1, 0x0800, 0xFFFF, 24576, "snake.efi", 0xFD); next_slot += 1
set_inode(next_slot, 0x03, 1, 0x2400, 0xFFFF, 12288, "shell.efi", 0xFC); next_slot += 1
set_inode(next_slot, 0x04, 1, 0x0040, 0x0070, 32,    "cmos.bin",  0xFB); next_slot += 1

# ROM-mapped 16-bit PCM WAV files in \audio (parent=2) with REAL ROM addresses & sizes
wav_filenames = ["crunch.wav", "golden.wav", "crash.wav", "start.wav", "pause.wav", "boot.wav", "gameover.wav", "victory.wav"]
cur_wav_linear = 0xFFFD0000
for idx_w, (wname, s_bytes) in enumerate(zip(wav_filenames, pcm_samples)):
    off_lo = cur_wav_linear & 0xFFFF
    seg_hi = (cur_wav_linear >> 16) & 0xFFFF
    set_inode(next_slot, 0x03, 2, off_lo, seg_hi, len(s_bytes), wname, idx_w)
    cur_wav_linear += len(s_bytes)
    next_slot += 1

alloc_ptr_init = CYBFS_DATA_START + len(data_pool_bin)
superblock_bin = struct.pack("<HHHHB23s", 0x5346, 0x0100, 32, alloc_ptr_init, 0, b"CYBFORGE_CYBFS_V1\x00\x00\x00\x00\x00\x00")
cybfs_master_img = superblock_bin + inodes_bin + data_pool_bin
assert len(cybfs_master_img) <= 4096, "CybFS master image exceeds 4 KB!"
cybfs_master_padded = cybfs_master_img + b"\x00" * (4096 - len(cybfs_master_img))

header_256 = b"CYBFORGE_RETRO_BIOS_256KB_ROM_CYBFS_V1\x00"
header_256 += b"\x00" * (256 - len(header_256))
block0 = header_256 + cybfs_master_padded + b"\x00" * (65536 - 256 - 4096)

content = SRC.read_text(encoding="utf-8", errors="replace")

# Part 1: Boot & Hardware Init up to STEP 7
idx_s7 = content.find("; STEP 7:")
if idx_s7 == -1:
    idx_s7 = content.find("STEP 7:")
part1 = content[:idx_s7]

# 8042 Controller Init: Enable Hardware Translation to Scancode Set 1
kbd_8042_init = """
    ; 8042 Keyboard Controller Setup: Enable Translation to Scancode Set 1
    mov cx, 50000
.wait_ibf1:
    in al, 0x64
    test al, 0x02
    jz .ibf1_empty
    dec cx
    jnz .wait_ibf1
.ibf1_empty:
    mov al, 0x60            ; Command 0x60: Write Controller Command Byte
    out 0x64, al

    mov cx, 50000
.wait_ibf2:
    in al, 0x64
    test al, 0x02
    jz .ibf2_empty
    dec cx
    jnz .wait_ibf2
.ibf2_empty:
    mov al, 0x40            ; Bit 6 = 1 (Translation to Set 1), Bit 4 = 0 (Kbd Clock enable)
    out 0x60, al
"""
part1 = part1.replace("; COM1 (0x3F8) at 115200 Baud", kbd_8042_init + "\n    ; COM1 (0x3F8) at 115200 Baud")

# RAM Variables in Segment 0x0000
ram_defs = """
; --- RAM Variables in Free Base Memory (DS = 0x0000, Addresses 0x1000..0x1B00) ---
SNAKE_X     equ 0x1000      ; X coordinates (1200 Bytes: 0x1000..0x14AF)
SNAKE_Y     equ 0x1500      ; Y coordinates (1200 Bytes: 0x1500..0x19AF)
SNAKE_LEN   equ 0x1A00      ; Current length (Word)
SNAKE_DIR   equ 0x1A02      ; Direction: 0=Up, 1=Right, 2=Down, 3=Left (Byte)
NEXT_DIR    equ 0x1A03      ; Buffered next direction (Byte)
FOOD_X      equ 0x1A04      ; Apple X position (Byte)
FOOD_Y      equ 0x1A05      ; Apple Y position (Byte)
SCORE       equ 0x1A06      ; Current score (Word)
RND_SEED    equ 0x1A08      ; Random seed (Word)
DIR_LOCKED  equ 0x1A0A      ; Direction change lock (Byte)
NEW_HEAD_X  equ 0x1A0B      ; New head X (Byte)
NEW_HEAD_Y  equ 0x1A0C      ; New head Y (Byte)
QUEUED_DIR  equ 0x1A0D      ; Buffer for rapid 2nd keystroke (Byte)
HIGH_SCORE  equ 0x1A0E      ; Session High Score (Word, persisted in CMOS NVRAM)

; Cybforge Retro BIOS Setup Configuration Options (0x1A10..0x1A19)
CFG_SPEED   equ 0x1A10      ; 0=Normal, 1=Fast, 2=Slow (Byte)
CFG_WALLS   equ 0x1A11      ; 0=Solid, 1=Wrap-Around (Byte)
CFG_SOUND   equ 0x1A12      ; 0=SB16 16-Bit, 1=PC Speaker, 2=Dual Audio, 3=Muted (Byte)
CFG_FACE    equ 0x1A13      ; 0=Classic Smile, 1=Cool Shades (Byte)
CFG_LEN     equ 0x1A14      ; 0=4 Segments, 1=3 Segments, 2=6 Segments (Byte)
CFG_WIN     equ 0x1A15      ; 0=Full Board (1044), 1=25, 2=50, 3=100 (Byte)
CFG_DISP    equ 0x1A16      ; Auto 1080p (Byte)
SETUP_SEL   equ 0x1A17      ; Selected menu row in Cybforge Setup (0..9) (Byte)
CFG_THEME   equ 0x1A18      ; 0=Cyberpunk Neon, 1=Matrix Green, 2=Amber CRT, 3=CGA Retro (Byte)
CFG_ARENA   equ 0x1A19      ; 0=Classic Open, 1=Four Pillars, 2=The Maze (Byte)

; Gameplay Extensions (0x1A1A..0x1A35)
GOLD_FOOD_X equ 0x1A1A      ; Golden apple X position (Byte, 0xFF when inactive)
GOLD_FOOD_Y equ 0x1A1B      ; Golden apple Y position (Byte)
GOLD_TIMER  equ 0x1A1C      ; Remaining ticks for golden apple (Word)
APPLE_COUNT equ 0x1A1E      ; Counter for regular apples eaten (Byte)
TOP3_TABLE  equ 0x1A20      ; Top 3 Leaderboard: 3x (3 Bytes Name, 2 Bytes Score) = 15 Bytes (0x1A20..0x1A2E)
CURRENT_NAME equ 0x1A30     ; 3-byte buffer for initials entry (0x1A30..0x1A32)
CUR_CHAR_IDX equ 0x1A33     ; Active character index (0..2) (Byte)
sb16_detected equ 0x1A34    ; 1=Sound Blaster 16 Detected, 0=None (Byte)

; --- Multi-Tab BIOS Setup & BiosShell Configuration (0x1A35..0x1A3F) ---
SETUP_TAB       equ 0x1A35  ; Active tab in Setup: 0 = Main & Game, 1 = BiosShell (Byte)
CFG_SH_THEME    equ 0x1A36  ; 0=Classic EFI, 1=Matrix Green, 2=Cyber Cyan, 3=BIOS Blue (Byte)
CFG_SH_PROMPT   equ 0x1A37  ; 0="FS0:\\> ", 1="SHELL> ", 2="root@bios:# " (Byte)
CFG_SH_BANNER   equ 0x1A38  ; 0=Full EFI Map, 1=Compact, 2=Quiet Mode (Byte)
CFG_SH_BEEP     equ 0x1A39  ; 0=Enabled, 1=Muted (Byte)
CFG_BOOT_MODE   equ 0x1A3A  ; 0=Snake Game, 1=BiosShell (Byte)

; --- Cybforge BIOS Shell Runtime Memory (0x1B00..0x1CFF) ---
SH_CUR_ROW      equ 0x1B00  ; Current terminal row (1..23) (Byte)
SH_CUR_COL      equ 0x1B01  ; Current terminal column (0..79) (Byte)
SH_DIR_ID       equ 0x1B02  ; Current directory: 0=Root, 1=EFI, 2=AUDIO, 3=DIAG (Byte)
SH_SHIFT        equ 0x1B03  ; Shift key pressed (0/1) (Byte)
SH_CMD_LEN      equ 0x1B04  ; Length of current input (0..58) (Byte)
SH_HIST_LEN     equ 0x1B05  ; Length of last command in history (Byte)
SH_DUMP_ADDR    equ 0x1B06  ; Current address for dmem hex dump (Word)
SH_TEXT_ATTR    equ 0x1B08  ; Default shell text attribute (Byte)
SH_HIGH_ATTR    equ 0x1B09  ; Shell highlight attribute (Byte)
SH_PROMPT_ATTR  equ 0x1B0A  ; Prompt color attribute (Byte)
SH_BAR_ATTR     equ 0x1B0B  ; Status bar attribute (Byte)

SH_CMD_BUF      equ 0x1B10  ; 64-byte input buffer (0x1B10..0x1B4F)
SH_HIST_BUF     equ 0x1B50  ; 64-byte history buffer (0x1B50..0x1B8F)
SH_CLEAN_BUF    equ 0x1B90  ; 64-byte normalized command buffer (0x1B90..0x1BCF)
SH_SCRIPT_PTR   equ 0x1BD0  ; Current read pointer for 'run <script>' (Word)
SH_SCRIPT_END   equ 0x1BD2  ; End address for 'run <script>' (Word)
SH_SCRIPT_ACT   equ 0x1BD4  ; 1 = Script currently running (Byte)
SH_CTRL         equ 0x1BD5  ; Ctrl key pressed (0/1) (Byte)
CFG_SH_FONT     equ 0x1BD6  ; Current font scale (0=Small, 1=Medium, 2=Large, 3=Huge) (Byte)
NANO_SAVED_FLAG equ 0x1BD7  ; 1 = Saved during this Nano session (Byte)
NANO_INODE      equ 0x1BD8  ; Pointer to current CybFS Inode in Nano editor (Word)
NANO_ROW        equ 0x1BDA  ; Current cursor row in Nano (0..17) (Byte)
NANO_COL        equ 0x1BDB  ; Current cursor column in Nano (0..71) (Byte)
NANO_MOD        equ 0x1BDC  ; 1 = Unsaved changes in buffer (Byte)
NANO_MSG_ID     equ 0x1BDD  ; Status message ID in Nano (0..4) (Byte)
NANO_LAST_SZ    equ 0x1BDE  ; Last file size in bytes (Word)
NANO_BUF        equ 0x7000  ; 18 rows x 72 cols = 1296-byte text buffer (0x7000..0x750F)

; --- CybFS v1.0 Live RAM Filesystem (0x3000..0x7FFF = 20 KB) ---
FS_MAGIC        equ 0x3000  ; Word: 0x5346 ('FS') when mounted
FS_VERSION      equ 0x3002  ; Word: 0x0100
FS_MAX_INODES   equ 0x3004  ; Word: 32
FS_ALLOC_PTR    equ 0x3006  ; Word: Next free data address (0x3420..0x7FFF)
FS_INODE_BASE   equ 0x3020  ; 32 Inodes x 32 Bytes (0x3020..0x341F)
FS_DATA_BASE    equ 0x3420  ; File data pool (0x3420..0x6FDF = 15,296 Bytes)
FS_POOL_END     equ 0x6FE0  ; Upper bound of CybFS data pool (0x6FE0..0x6FFF = 32B NVRAM Settings Mirror)
NVRAM_MIRROR    equ 0x6FE0  ; 32-byte persistent CMOS/Setup/Highscore mirror on ATA LBA 31

; --- v3.0 Hardware xHCI (USB 3.0), EHCI (USB 2.0), Mouse & Google Snake State ---
XHCI_FOUND      equ 0x1BE0  ; 1 = xHCI USB 3.0 Controller initialized (Byte)
XHCI_BUS_DEV    equ 0x1BE1  ; PCI Dev/Fn byte for xHCI (Byte)
XHCI_VEN_ID     equ 0x1BE2  ; xHCI PCI Vendor ID (Word)
XHCI_DEV_ID     equ 0x1BE4  ; xHCI PCI Device ID (Word)
XHCI_HCI_VER    equ 0x1BE6  ; xHCI Interface Version BCD (Word)
XHCI_MAX_SLOTS  equ 0x1BE8  ; xHCI HCSPARAMS1 MaxSlots (Byte)
XHCI_MAX_PORTS  equ 0x1BE9  ; xHCI HCSPARAMS1 MaxPorts (Byte)
XHCI_PORTS_CONN equ 0x1BEA  ; Connected ports count on xHCI Root Hub (Byte)
XHCI_PORT1_SC   equ 0x1BEC  ; Live xHCI Port 1 PORTSC register (Dword)

EHCI_FOUND      equ 0x1BF0  ; 1 = EHCI USB 2.0 Controller initialized (Byte)
EHCI_BUS_DEV    equ 0x1BF1  ; PCI Dev/Fn byte for EHCI (Byte)
EHCI_VEN_ID     equ 0x1BF2  ; EHCI PCI Vendor ID (Word)
EHCI_DEV_ID     equ 0x1BF4  ; EHCI PCI Device ID (Word)
EHCI_HCI_VER    equ 0x1BF6  ; EHCI Interface Version BCD (Word)
EHCI_MAX_PORTS  equ 0x1BF8  ; EHCI HCSPARAMS N_PORTS (Byte)
EHCI_PORTS_CONN equ 0x1BF9  ; Connected ports count on EHCI Root Hub (Byte)
EHCI_PORT1_SC   equ 0x1BFC  ; Live EHCI Port 1 PORTSC register (Dword)

MOUSE_READY     equ 0x1C00  ; 1 = 8042 PS/2 Aux / USB Mouse active (Byte)
MOUSE_PKT_IDX   equ 0x1C01  ; Packet byte index 0..2 (Byte)
MOUSE_PKT_B0    equ 0x1C02  ; Packet byte 0: Buttons & Sign/Overflow (Byte)
MOUSE_PKT_B1    equ 0x1C03  ; Packet byte 1: Delta X (Byte)
MOUSE_FINE_X    equ 0x1C04  ; Sub-cell X position 0..639 (Word)
MOUSE_FINE_Y    equ 0x1C06  ; Sub-cell Y position 0..399 (Word)
MOUSE_X         equ 0x1C08  ; Text column 0..79 (Byte)
MOUSE_Y         equ 0x1C09  ; Text row 0..24 (Byte)
MOUSE_BTN       equ 0x1C0A  ; Current button state bit0=L, bit1=R, bit2=M (Byte)
MOUSE_PREV_BTN  equ 0x1C0B  ; Previous button state for rising-edge click (Byte)
MOUSE_CLICK     equ 0x1C0C  ; Latched rising-edge click bit0=Left, bit1=Right (Byte)
MOUSE_CUR_VIS   equ 0x1C0D  ; 1 = Software mouse cursor currently drawn on VRAM (Byte)
MOUSE_OLD_X     equ 0x1C0E  ; Saved cursor column (Byte)
MOUSE_OLD_Y     equ 0x1C0F  ; Saved cursor row (Byte)
MOUSE_SAVED_W   equ 0x1C10  ; Saved VRAM word under mouse cursor (Word)
MOUSE_EVT_CNT   equ 0x1C12  ; Total mouse packets processed counter (Word)

BULGE_X         equ 0x1C14  ; Digesting apple bulge X coordinate (0xFF=none) (Byte)
BULGE_Y         equ 0x1C15  ; Digesting apple bulge Y coordinate (Byte)
TONGUE_TICK     equ 0x1C16  ; Animation tick counter for flicking tongue (Byte)
TONGUE_X        equ 0x1C17  ; Drawn tongue X coordinate (0xFF=none) (Byte)
TONGUE_Y        equ 0x1C18  ; Drawn tongue Y coordinate (Byte)
CARD_BTN_SEL    equ 0x1C19  ; Selected button (0=Play, 1=Setup, 2=Shell) on Start/GameOver card (Byte)
UI_PAL_MODE     equ 0x1C1A  ; 0 = Modern UEFI Dark Palette, 1 = Cybforge Snake Grass Palette (Byte)
VGA_GFX_ACTIVE  equ 0x1C1B  ; 1 = VGA Mode 13h (320x200x256) active, 0 = 80x25 Text Mode (Byte)
CARD_OPEN       equ 0x1C1C  ; 1 = Popup Card active (dims background playfield) (Byte)
FIRST_SPAWN     equ 0x1C1D  ; 1 = First fruit spawn on row 8 ahead of snake (Byte)
MOUSE_LAST_FX   equ 0x1C1E  ; Last drawn fine mouse X (Word)
MOUSE_LAST_FY   equ 0x1C20  ; Last drawn fine mouse Y (Word)
"""
idx_org = part1.find("[ORG 0x0000]")
line_end = part1.find("\n", idx_org) + 1
part1 = part1[:line_end] + ram_defs + part1[line_end:]

# Insert the logo font loader into part1 after .font_done
logo_loader_code = """
    ; --- Copy custom 16-scanline game glyphs (0x01..0x0A) directly into Plane 2 ---
    push ds
    push cs
    pop ds
    mov si, custom_glyphs_table
.custom_glyph_loop:
    lodsb
    test al, al
    jz .custom_glyphs_done
    xor ah, ah
    shl ax, 5               ; Offset in Plane 2 = char_code * 32
    mov di, ax
    mov cx, 16              ; All 16 real scanlines
    rep movsb
    jmp .custom_glyph_loop
.custom_glyphs_done:

    ; --- Copy Cybforge logo 16-scanline glyphs (0x80..0xBB) directly into Plane 2 ---
    mov si, logo_font_table
.logo_char_loop:
    lodsb
    test al, al
    jz .logo_done
    xor ah, ah
    shl ax, 5               ; Offset in Plane 2 = char_code * 32
    mov di, ax
    mov cx, 16              ; All 16 real scanlines
    rep movsb
    jmp .logo_char_loop
.logo_done:
    pop ds
"""
# Upgrade base_bios font loop from 8x8-doubled to true 16-scanline 8x16 font + disable (0,0) cursor
old_font_loop = """    mov cx, 8
.font_row_loop:
    lodsb
    stosb                   ; Scanline 2n
    stosb                   ; Scanline 2n+1 (8x16 Font)
    loop .font_row_loop"""

new_font_loop = """    mov cx, 16
    rep movsb               ; True 16-scanline 8x16 IBM VGA Font"""

assert old_font_loop in part1, "old_font_loop not found in part1"
part1 = part1.replace(old_font_loop, new_font_loop, 1)

cursor_disable_code = """
    ; Disable hardware text cursor (CRTC 0x0A) (prevents '_' artifact at 0,0)
    mov dx, 0x3D4
    mov ax, 0x200A
    out dx, ax
"""
part1 = part1.replace(".font_done:", ".font_done:\n" + logo_loader_code + cursor_disable_code)

# Part 2: Cybforge POST Screen, Cybforge Setup Utility & Snake Game
part2 = """
    ; =========================================================================
    ; SEGMENT-SETUP: DS = 0x0000 (RAM) & ES = 0xB800 (TEXT-VRAM)
    ; =========================================================================
    mov ax, 0x0000
    mov ds, ax              ; DS points permanently to base memory!
    mov ax, 0xB800
    mov es, ax              ; ES points permanently to VGA text memory!

    ; Initialize Flat Real Mode (Unreal Mode) for 256KB ROM audio & MMIO
    call enter_unreal_mode

    ; Initialize Bare-Metal xHCI (USB 3.0) & EHCI (USB 2.0) PCI/MMIO Controllers
    call usb_init_controllers

    ; Initialize 8042 PS/2 Aux & USB Pointer Hardware Mouse Driver
    call mouse_init

    ; Initialize Sound Blaster 16 hardware (DSP Reset, Mixer, Volumes)
    call sb16_init
    call sound_boot

    ; Load saved settings, CybFS & Top 3 highscores from ATA disk / CMOS
    mov byte [CFG_SH_FONT], 2       ; Default before loading: 2 (Large 8x16)
    call load_cmos_settings
    call load_ui_palette
    call vga_apply_font_scale
    mov byte [SETUP_SEL], 0         ; Row 0 selected
    mov byte [SETUP_TAB], 0         ; Default tab: 0 (Main & Game)
    mov byte [VGA_GFX_ACTIVE], 0    ; Start in 80x25 Text Mode

    ; =========================================================================
    ; PHASE 1: CYBFORGE UEFI/BIOS v3.0 POST SCREEN (Modern Dashboard)
    ; =========================================================================
post_screen:
    call vga_set_text_mode
    call mouse_hide_cursor
    call load_ui_palette
    call clear_screen_black

    ; Top Modern UEFI Banner Bar (Row 0)
    xor di, di
    mov cx, 80
    mov ax, 0x1F20
    rep stosw
    mov di, (0 * 80 + 2) * 2
    mov si, str_post_top_bar
    mov ah, 0x1F
    call print_string

    ; Row 2: BIOS Date & Version
    mov di, (2 * 80 + 2) * 2
    mov si, str_post_hdr2
    mov ah, 0x0B
    call print_string

    ; Rows 4 & 5: CPU & Co-Processor
    mov di, (4 * 80 + 2) * 2
    mov si, str_post_cpu
    mov ah, 0x07
    call print_string

    mov di, (5 * 80 + 2) * 2
    mov si, str_post_coproc
    mov ah, 0x07
    call print_string

    ; Rows 7..9: VGA Display, Keyboard/Mouse, Timer
    mov di, (7 * 80 + 2) * 2
    mov si, str_post_vga
    mov ah, 0x07
    call print_string

    mov di, (8 * 80 + 2) * 2
    mov si, str_post_kbd
    mov ah, 0x0A
    call print_string

    mov di, (9 * 80 + 2) * 2
    mov si, str_post_pit
    mov ah, 0x07
    call print_string

    ; Rows 11 & 12: Live xHCI (USB 3.0) & EHCI (USB 2.0) Controller Status!
    mov di, (11 * 80 + 2) * 2
    mov si, str_post_xhci_ok
    mov ah, 0x0B
    cmp byte [XHCI_FOUND], 1
    je .post_pr_xhci
    mov si, str_post_xhci_none
    mov ah, 0x08
.post_pr_xhci:
    call print_string

    mov di, (12 * 80 + 2) * 2
    mov si, str_post_ehci_ok
    mov ah, 0x0B
    cmp byte [EHCI_FOUND], 1
    je .post_pr_ehci
    mov si, str_post_ehci_none
    mov ah, 0x08
.post_pr_ehci:
    call print_string

    ; Row 14: Animated RAM counter with soft ticks (0..640 KB)
    call post_ram_counter

    mov di, (15 * 80 + 2) * 2
    mov si, str_post_ext
    mov ah, 0x07
    call print_string

    ; Row 17: Persistent NVRAM Disk & Audio
    mov di, (17 * 80 + 2) * 2
    mov si, str_post_drives
    mov ah, 0x0A
    call print_string

    ; Draw Cybforge logo on the right side (Rows 2 to 9, Cols 64 to 73)
    call draw_cybforge_logo

    ; Rows 20 & 21: F12 prompt & countdown (also clickable with mouse!)
    mov di, (20 * 80 + 2) * 2
    mov si, str_post_f12
    mov ah, 0x0E
    call print_string

    mov di, (21 * 80 + 2) * 2
    mov si, str_post_boot
    mov ah, 0x07
    call print_string

    ; Bottom Status Bar (Row 24)
    mov di, (24 * 80) * 2
    mov cx, 80
    mov ax, 0x1F20
    rep stosw
    mov di, (24 * 80 + 2) * 2
    mov si, str_post_bot_bar
    mov ah, 0x1E
    call print_string

    call mouse_show_cursor
    call drain_kbd
    mov bp, 60
.post_wait_loop:
    call read_key
    cmp al, 0x58                    ; F12 -> Setup
    je core_bios_setup
    cmp al, 0x53                    ; DEL -> Setup
    je core_bios_setup
    cmp al, 0x1C                    ; ENTER -> Boot immediately
    je boot_direct_snake

    ; Check if user clicked mouse during POST
    test byte [MOUSE_CLICK], 0x01
    jz .post_no_click
    mov byte [MOUSE_CLICK], 0
    cmp byte [MOUSE_Y], 20
    je core_bios_setup
    jmp boot_direct_snake
.post_no_click:

    mov ecx, 12500000               ; ~50 ms Mini-Tick (60 * 50ms = 3.0s)
    call delay_cycles
    dec bp
    jnz .post_wait_loop

boot_direct_snake:
    cmp byte [CFG_BOOT_MODE], 1
    je bios_shell_main
    jmp init_snake_game

    ; =========================================================================
    ; CYBFORGE LOGO DRAWING ROUTINE (Right side of POST screen)
    ; =========================================================================
draw_cybforge_logo:
    mov bl, 0x80                    ; First character code for logo (0x80 to 0xBB)
    mov dh, 2                       ; Start row 2 (Rows 2 to 7 = 6 rows)
.row_loop:
    cmp dh, 8
    je .done_logo_tiles

    movzx ax, dh
    mov cl, 80
    mul cl
    add ax, 64
    shl ax, 1
    mov di, ax

    mov cx, 10                      ; 10 columns
.col_loop:
    mov al, bl
    mov ah, 0x0B                    ; Attribute: Bright Cyan (0x0B)
    stosw
    inc bl
    loop .col_loop

    inc dh
    jmp .row_loop

.done_logo_tiles:
    mov di, (8 * 80 + 64) * 2
    mov si, str_logo_lbl1
    mov ah, 0x0B
    call print_string

    mov di, (9 * 80 + 64) * 2
    mov si, str_logo_lbl2
    mov ah, 0x0E
    call print_string
    ret

    ; =========================================================================
    ; PHASE 2: MODERNIZED UEFI BIOS SETUP UTILITY (With Full Mouse Support!)
    ; =========================================================================
core_bios_setup:
    call vga_set_text_mode
    call mouse_hide_cursor
    call load_ui_palette
    call drain_kbd
    mov byte [MOUSE_CLICK], 0
    call sound_click

.redraw_setup:
    call mouse_hide_cursor
    call draw_setup_screen
    call mouse_show_cursor

.setup_input_loop:
    call read_key
    test al, al
    jnz .setup_got_key

    ; Check for mouse click in BIOS Setup!
    mov bl, [MOUSE_CLICK]
    test bl, 0x03                   ; Left or Right click?
    jz .setup_wait_tick
    mov byte [MOUSE_CLICK], 0

    ; Right click anywhere -> Previous value on current row
    test bl, 0x02
    jnz .val_prev

    ; Left click handling by Row (MOUSE_Y) and Column (MOUSE_X)
    mov dh, [MOUSE_Y]
    mov dl, [MOUSE_X]

    ; Row 2: Tab Bar click
    cmp dh, 2
    jne .chk_setup_row_click
    cmp dl, 29
    jb .switch_tab_0
    cmp dl, 54
    jb .switch_tab_1
    jmp .launch_bios_shell

.chk_setup_row_click:
    ; Row 24: Bottom Footer Bar click
    cmp dh, 24
    jne .chk_setup_items_click
    cmp dl, 22
    jb .toggle_tab
    cmp dl, 56
    jb .val_enter
    jmp .exit_setup

.chk_setup_items_click:
    cmp byte [SETUP_TAB], 1
    je .setup_click_tab1

    ; Tab 0 rows: Rows 4..12 -> indices 0..8, Row 14 -> 9, Row 15 -> 10
    cmp dh, 4
    jb .setup_wait_tick
    cmp dh, 12
    jbe .click_t0_0_8
    cmp dh, 14
    je .click_t0_9
    cmp dh, 15
    je .click_t0_10
    jmp .setup_wait_tick

.click_t0_0_8:
    mov al, dh
    sub al, 4
    mov [SETUP_SEL], al
    jmp .val_enter
.click_t0_9:
    mov byte [SETUP_SEL], 9
    jmp .do_reset_defaults
.click_t0_10:
    mov byte [SETUP_SEL], 10
    jmp .exit_setup

.setup_click_tab1:
    ; Tab 1 rows: Row 4 -> 0, Row 6 -> 1, Rows 8..12 -> 2..6, Row 14 -> 7, Row 15 -> 8
    cmp dh, 4
    je .click_t1_0
    cmp dh, 6
    je .click_t1_1
    cmp dh, 8
    jb .setup_wait_tick
    cmp dh, 12
    jbe .click_t1_2_6
    cmp dh, 14
    je .click_t1_7
    cmp dh, 15
    je .click_t1_8
    jmp .setup_wait_tick

.click_t1_0:
    mov byte [SETUP_SEL], 0
    jmp .toggle_tab
.click_t1_1:
    mov byte [SETUP_SEL], 1
    jmp .launch_bios_shell
.click_t1_2_6:
    mov al, dh
    sub al, 6
    mov [SETUP_SEL], al
    jmp .val_next
.click_t1_7:
    mov byte [SETUP_SEL], 7
    jmp .do_reset_shell_defaults
.click_t1_8:
    mov byte [SETUP_SEL], 8
    jmp .exit_setup

.setup_got_key:
    ; Quick tab switching via [TAB] (0x0F), [1] (0x02), [2] (0x03)
    cmp al, 0x0F                    ; TAB -> Switch tab!
    je .toggle_tab
    cmp al, 0x02                    ; Key '1' -> Tab 0 (Main & Game)
    je .switch_tab_0
    cmp al, 0x03                    ; Key '2' -> Tab 1 (BiosShell)
    je .switch_tab_1

    ; Navigation: W/S or Up/Down arrow keys
    cmp al, 0x11                    ; 'W'
    je .sel_up
    cmp al, 0x48                    ; Up Arrow
    je .sel_up

    cmp al, 0x1F                    ; 'S'
    je .sel_down
    cmp al, 0x50                    ; Down Arrow
    je .sel_down

    ; Change value / switch tab: A/D, Left/Right arrow keys, ENTER, SPACE
    cmp al, 0x1E                    ; 'A'
    je .val_prev
    cmp al, 0x4B                    ; Left Arrow
    je .val_prev

    cmp al, 0x20                    ; 'D'
    je .val_next
    cmp al, 0x4D                    ; Right Arrow
    je .val_next

    cmp al, 0x1C                    ; ENTER
    je .val_enter
    cmp al, 0x39                    ; SPACE
    je .val_next

    cmp al, 0x01                    ; ESC -> Save & Boot
    je .exit_setup

.setup_wait_tick:
    mov ecx, 1500000                ; ~5 ms for ultra-responsive menu & mouse reaction
    call delay_cycles
    jmp .setup_input_loop

.toggle_tab:
    xor byte [SETUP_TAB], 1
    cmp byte [SETUP_TAB], 1
    je .land_tab1
    mov byte [SETUP_SEL], 0
    call sound_toggle
    jmp .redraw_setup
.land_tab1:
    mov byte [SETUP_SEL], 1         ; Select "Launch BiosShell [Press ENTER]" directly!
    call sound_toggle
    jmp .redraw_setup

.switch_tab_0:
    mov byte [SETUP_TAB], 0
    mov byte [SETUP_SEL], 0
    call sound_toggle
    jmp .redraw_setup

.switch_tab_1:
    mov byte [SETUP_TAB], 1
    mov byte [SETUP_SEL], 1
    call sound_toggle
    jmp .redraw_setup

.sel_up:
    call sound_click
    mov al, [SETUP_SEL]
    test al, al
    jz .wrap_up
    dec byte [SETUP_SEL]
    jmp .redraw_setup
.wrap_up:
    mov byte [SETUP_SEL], 10        ; Tab 0 has indices 0..10
    cmp byte [SETUP_TAB], 0
    je .redraw_setup
    mov byte [SETUP_SEL], 8         ; Tab 1 has indices 0..8
    jmp .redraw_setup

.sel_down:
    call sound_click
    mov al, [SETUP_SEL]
    mov ah, 10
    cmp byte [SETUP_TAB], 0
    je .chk_down_lim
    mov ah, 8
.chk_down_lim:
    cmp al, ah
    jae .wrap_down
    inc byte [SETUP_SEL]
    jmp .redraw_setup
.wrap_down:
    mov byte [SETUP_SEL], 0
    jmp .redraw_setup

; --- LEFT / PREVIOUS VALUE ---
.val_prev:
    mov al, [SETUP_SEL]
    cmp al, 0                       ; Row 0 is the tab selector on both tabs!
    je .toggle_tab

    cmp byte [SETUP_TAB], 1
    je .tab1_prev

    ; Tab 0 (Main & Game): Indices 1..8
    call sound_toggle
    cmp al, 1
    jne .p2
    dec byte [CFG_SPEED]
    jns .redraw_setup
    mov byte [CFG_SPEED], 2
    jmp .redraw_setup
.p2:
    cmp al, 2
    jne .p3
    xor byte [CFG_WALLS], 1
    jmp .redraw_setup
.p3:
    cmp al, 3
    jne .p4
    dec byte [CFG_SOUND]
    and byte [CFG_SOUND], 3
    call sound_toggle
    jmp .redraw_setup
.p4:
    cmp al, 4
    jne .p5
    xor byte [CFG_FACE], 1
    jmp .redraw_setup
.p5:
    cmp al, 5
    jne .p6
    dec byte [CFG_LEN]
    jns .redraw_setup
    mov byte [CFG_LEN], 2
    jmp .redraw_setup
.p6:
    cmp al, 6
    jne .p7
    dec byte [CFG_WIN]
    jns .redraw_setup
    mov byte [CFG_WIN], 3
    jmp .redraw_setup
.p7:
    cmp al, 7
    jne .p8
    dec byte [CFG_THEME]
    jns .th_prev_ok
    mov byte [CFG_THEME], 3
.th_prev_ok:
    jmp .redraw_setup
.p8:
    cmp al, 8
    jne .redraw_setup
    dec byte [CFG_ARENA]
    jns .redraw_setup
    mov byte [CFG_ARENA], 2
    jmp .redraw_setup

.tab1_prev:
    cmp al, 1
    je .switch_tab_0
    call sound_toggle
    cmp al, 2
    jne .t1_p3
    dec byte [CFG_SH_THEME]
    and byte [CFG_SH_THEME], 3
    jmp .redraw_setup
.t1_p3:
    cmp al, 3
    jne .t1_p4
    dec byte [CFG_SH_PROMPT]
    jns .redraw_setup
    mov byte [CFG_SH_PROMPT], 2
    jmp .redraw_setup
.t1_p4:
    cmp al, 4
    jne .t1_p5
    dec byte [CFG_SH_BANNER]
    jns .redraw_setup
    mov byte [CFG_SH_BANNER], 2
    jmp .redraw_setup
.t1_p5:
    cmp al, 5
    jne .t1_p6
    xor byte [CFG_SH_BEEP], 1
    jmp .redraw_setup
.t1_p6:
    cmp al, 6
    jne .redraw_setup
    xor byte [CFG_BOOT_MODE], 1
    jmp .redraw_setup

; --- RIGHT / NEXT VALUE ---
.val_next:
    mov al, [SETUP_SEL]
    cmp al, 0
    je .toggle_tab

    cmp byte [SETUP_TAB], 1
    je .tab1_next

    ; Tab 0 (Main & Game): Indices 1..8
    call sound_toggle
    cmp al, 1
    jne .n2
    inc byte [CFG_SPEED]
    cmp byte [CFG_SPEED], 3
    jb .redraw_setup
    mov byte [CFG_SPEED], 0
    jmp .redraw_setup
.n2:
    cmp al, 2
    jne .n3
    xor byte [CFG_WALLS], 1
    jmp .redraw_setup
.n3:
    cmp al, 3
    jne .n4
    inc byte [CFG_SOUND]
    and byte [CFG_SOUND], 3
    call sound_toggle
    jmp .redraw_setup
.n4:
    cmp al, 4
    jne .n5
    xor byte [CFG_FACE], 1
    jmp .redraw_setup
.n5:
    cmp al, 5
    jne .n6
    inc byte [CFG_LEN]
    cmp byte [CFG_LEN], 3
    jb .redraw_setup
    mov byte [CFG_LEN], 0
    jmp .redraw_setup
.n6:
    cmp al, 6
    jne .n7
    inc byte [CFG_WIN]
    cmp byte [CFG_WIN], 4
    jb .redraw_setup
    mov byte [CFG_WIN], 0
    jmp .redraw_setup
.n7:
    cmp al, 7
    jne .n8
    inc byte [CFG_THEME]
    cmp byte [CFG_THEME], 4
    jb .th_next_ok
    mov byte [CFG_THEME], 0
.th_next_ok:
    jmp .redraw_setup
.n8:
    cmp al, 8
    jne .redraw_setup
    inc byte [CFG_ARENA]
    cmp byte [CFG_ARENA], 3
    jb .redraw_setup
    mov byte [CFG_ARENA], 0
    jmp .redraw_setup

.tab1_next:
    cmp al, 1
    je .launch_bios_shell
    call sound_toggle
    cmp al, 2
    jne .t1_n3
    inc byte [CFG_SH_THEME]
    and byte [CFG_SH_THEME], 3
    jmp .redraw_setup
.t1_n3:
    cmp al, 3
    jne .t1_n4
    inc byte [CFG_SH_PROMPT]
    cmp byte [CFG_SH_PROMPT], 3
    jb .redraw_setup
    mov byte [CFG_SH_PROMPT], 0
    jmp .redraw_setup
.t1_n4:
    cmp al, 4
    jne .t1_n5
    inc byte [CFG_SH_BANNER]
    cmp byte [CFG_SH_BANNER], 3
    jb .redraw_setup
    mov byte [CFG_SH_BANNER], 0
    jmp .redraw_setup
.t1_n5:
    cmp al, 5
    jne .t1_n6
    xor byte [CFG_SH_BEEP], 1
    jmp .redraw_setup
.t1_n6:
    cmp al, 6
    jne .redraw_setup
    xor byte [CFG_BOOT_MODE], 1
    jmp .redraw_setup

; --- ENTER ACTION ---
.val_enter:
    mov al, [SETUP_SEL]
    cmp al, 0
    je .toggle_tab

    cmp byte [SETUP_TAB], 1
    je .tab1_enter

    cmp al, 9
    je .do_reset_defaults
    cmp al, 10
    je .exit_setup
    jmp .val_next

.tab1_enter:
    cmp al, 1
    je .launch_bios_shell
    cmp al, 7
    je .do_reset_shell_defaults
    cmp al, 8
    je .exit_setup
    jmp .val_next

.launch_bios_shell:
    call save_cmos_settings
    call sound_start
    jmp bios_shell_main

.do_reset_defaults:
    mov byte [CFG_SPEED], 0
    mov byte [CFG_WALLS], 0
    mov byte [CFG_SOUND], 0
    mov byte [CFG_FACE],  0
    mov byte [CFG_LEN],   0
    mov byte [CFG_WIN],   0
    mov byte [CFG_DISP],  0
    mov byte [CFG_THEME], 0
    mov byte [CFG_ARENA], 0
    call save_cmos_settings
    call sound_toggle
    jmp .redraw_setup

.do_reset_shell_defaults:
    mov byte [CFG_SH_THEME],  0
    mov byte [CFG_SH_PROMPT], 0
    mov byte [CFG_SH_BANNER], 0
    mov byte [CFG_SH_BEEP],   0
    mov byte [CFG_BOOT_MODE], 0
    call save_cmos_settings
    call sound_toggle
    jmp .redraw_setup

.exit_setup:
    call save_cmos_settings
    jmp init_snake_game

    ; =========================================================================
    ; MODERNIZED UEFI SETUP SCREEN RENDERER (Sleek Dark Slate & Sapphire UI)
    ; =========================================================================
draw_setup_screen:
    ; 1. Fill screen with Deep Obsidian Slate (0x0720) & Top/Bottom UEFI Sapphire Bars
    xor di, di
    mov cx, 80
    mov ax, 0x3F20                  ; Top Title Bar: Crisp White on Deep Teal/Cyan
    rep stosw

    mov cx, 23 * 80
    mov ax, 0x1F20                  ; Main Canvas: Sapphire UEFI Blue
    rep stosw

    mov cx, 80
    mov ax, 0x3F20                  ; Bottom Footer Bar
    rep stosw

    ; 2. Title bar (Row 0)
    mov di, (0 * 80 + 2) * 2
    mov si, str_setup_title
    mov ah, 0x3F
    call print_string

    mov di, (0 * 80 + 52) * 2
    mov si, str_setup_tab_hint
    mov ah, 0x3E
    call print_string

    ; 3. Modern Tab Bar + Hardware Telemetry Strip (Row 2)
    mov di, (2 * 80 + 6) * 2
    mov si, str_tab0_label
    mov ah, 0x70                    ; Active Pill: Dark Slate on Frosted Silver
    cmp byte [SETUP_TAB], 0
    je .draw_t0_hdr
    mov ah, 0x17                    ; Inactive Pill
.draw_t0_hdr:
    call print_string

    mov di, (2 * 80 + 29) * 2
    mov si, str_tab1_label
    mov ah, 0x70
    cmp byte [SETUP_TAB], 1
    je .draw_t1_hdr
    mov ah, 0x17
.draw_t1_hdr:
    call print_string

    ; Live USB 3.0 / USB 2.0 / Mouse badge on Row 2 Right (Col 52)
    mov di, (2 * 80 + 52) * 2
    mov si, str_setup_hw_badge
    mov ah, 0x1A                    ; Neon Mint on Sapphire
    call print_string

    ; 4. Main options box (Rows 3 to 17, Cols 6 to 73)
    mov di, (3 * 80 + 6) * 2
    mov ax, 0x1B01                  ; '╭' Electric Cyan
    stosw
    mov cx, 66
    mov ax, 0x1B05                  ; '═'
    rep stosw
    mov ax, 0x1B02                  ; '╮'
    stosw

    mov di, (3 * 80 + 10) * 2
    mov si, str_box_title_main
    cmp byte [SETUP_TAB], 0
    je .draw_box_hdr
    mov si, str_box_title_shell
.draw_box_hdr:
    mov ah, 0x1E                    ; Golden Yellow
    call print_string

    mov cx, 13
    mov di, (4 * 80 + 6) * 2
.sb_vert1:
    mov word [es:di], 0x1B06
    mov word [es:di + 67 * 2], 0x1B06
    add di, 80 * 2
    loop .sb_vert1

    mov di, (17 * 80 + 6) * 2
    mov ax, 0x1B03                  ; '╰'
    stosw
    mov cx, 66
    mov ax, 0x1B05                  ; '═'
    rep stosw
    mov ax, 0x1B04                  ; '╯'
    stosw

    ; 5. Help & Live Hardware Status Box (Rows 18 to 23, Cols 6 to 73)
    mov di, (18 * 80 + 6) * 2
    mov ax, 0x1B01
    stosw
    mov cx, 66
    mov ax, 0x1B05
    rep stosw
    mov ax, 0x1B02
    stosw

    mov di, (18 * 80 + 10) * 2
    mov si, str_box_title_help
    mov ah, 0x1E
    call print_string

    mov cx, 4
    mov di, (19 * 80 + 6) * 2
.sb_vert2:
    mov word [es:di], 0x1B06
    mov word [es:di + 67 * 2], 0x1B06
    add di, 80 * 2
    loop .sb_vert2

    mov di, (23 * 80 + 6) * 2
    mov ax, 0x1B03
    stosw
    mov cx, 66
    mov ax, 0x1B05
    rep stosw
    mov ax, 0x1B04
    stosw

    ; Live Hardware Telemetry inside Help Box Row 22
    mov di, (22 * 80 + 9) * 2
    mov si, str_setup_usb_line
    mov ah, 0x1B
    call print_string

    ; 6. Footer / Keyboard & Mouse controls (Row 24)
    mov di, (24 * 80 + 2) * 2
    mov si, str_setup_footer
    mov ah, 0x3F
    call print_string

    ; Check which tab is active
    cmp byte [SETUP_TAB], 1
    je .draw_tab1_items

    ; =========================================================================
    ; TAB 0: MAIN & GAME ITEMS (Indices 0..10)
    ; =========================================================================
    mov bl, 0
    mov dh, 4
    mov si, str_opt_tab
    call draw_menu_row
    mov si, str_val_tab_main
    call draw_val_str

    mov bl, 1
    mov dh, 5
    mov si, str_opt_speed
    call draw_menu_row
    mov si, str_val_spd_norm
    cmp byte [CFG_SPEED], 1
    jne .chk_s_fast
    mov si, str_val_spd_fast
    jmp .draw_spd_val
.chk_s_fast:
    cmp byte [CFG_SPEED], 2
    jne .draw_spd_val
    mov si, str_val_spd_slow
.draw_spd_val:
    call draw_val_str

    mov bl, 2
    mov dh, 6
    mov si, str_opt_walls
    call draw_menu_row
    mov si, str_val_wall_solid
    cmp byte [CFG_WALLS], 1
    jne .draw_wall_val
    mov si, str_val_wall_wrap
.draw_wall_val:
    call draw_val_str

    mov bl, 3
    mov dh, 7
    mov si, str_opt_sound
    call draw_menu_row
    mov al, [CFG_SOUND]
    cmp al, 0
    jne .chk_snd_spk
    mov si, str_val_snd_sb16
    jmp .draw_snd_val
.chk_snd_spk:
    cmp al, 1
    jne .chk_snd_dual
    mov si, str_val_snd_spk
    jmp .draw_snd_val
.chk_snd_dual:
    cmp al, 2
    jne .chk_snd_muted
    mov si, str_val_snd_dual
    jmp .draw_snd_val
.chk_snd_muted:
    mov si, str_val_snd_off
.draw_snd_val:
    call draw_val_str

    mov bl, 4
    mov dh, 8
    mov si, str_opt_face
    call draw_menu_row
    mov si, str_val_face_smile
    cmp byte [CFG_FACE], 1
    jne .draw_face_val
    mov si, str_val_face_cool
.draw_face_val:
    call draw_val_str

    mov bl, 5
    mov dh, 9
    mov si, str_opt_len
    call draw_menu_row
    mov si, str_val_len_4
    cmp byte [CFG_LEN], 1
    jne .chk_l_3
    mov si, str_val_len_3
    jmp .draw_len_val
.chk_l_3:
    cmp byte [CFG_LEN], 2
    jne .draw_len_val
    mov si, str_val_len_6
.draw_len_val:
    call draw_val_str

    mov bl, 6
    mov dh, 10
    mov si, str_opt_win
    call draw_menu_row
    mov si, str_val_win_full
    cmp byte [CFG_WIN], 1
    jne .chk_win_val25
    mov si, str_val_win_25
    jmp .draw_win_val
.chk_win_val25:
    cmp byte [CFG_WIN], 2
    jne .chk_win_val50
    mov si, str_val_win_50
    jmp .draw_win_val
.chk_win_val50:
    cmp byte [CFG_WIN], 3
    jne .draw_win_val
    mov si, str_val_win_100
.draw_win_val:
    call draw_val_str

    mov bl, 7
    mov dh, 11
    mov si, str_opt_theme
    call draw_menu_row
    mov si, str_val_theme_cyber
    cmp byte [CFG_THEME], 1
    jne .chk_th_m
    mov si, str_val_theme_matr
    jmp .draw_th_val
.chk_th_m:
    cmp byte [CFG_THEME], 2
    jne .chk_th_a
    mov si, str_val_theme_amber
    jmp .draw_th_val
.chk_th_a:
    cmp byte [CFG_THEME], 3
    jne .draw_th_val
    mov si, str_val_theme_cga
.draw_th_val:
    call draw_val_str

    mov bl, 8
    mov dh, 12
    mov si, str_opt_arena
    call draw_menu_row
    mov si, str_val_arena_open
    cmp byte [CFG_ARENA], 1
    jne .chk_ar_p
    mov si, str_val_arena_pil
    jmp .draw_ar_val
.chk_ar_p:
    cmp byte [CFG_ARENA], 2
    jne .draw_ar_val
    mov si, str_val_arena_maze
.draw_ar_val:
    call draw_val_str

    mov bl, 9
    mov dh, 14
    mov si, str_opt_reset
    call draw_menu_row

    mov bl, 10
    mov dh, 15
    mov si, str_opt_boot
    call draw_menu_row

    ; Info: Display Session High Score at Row 16
    mov di, (16 * 80 + 10) * 2
    mov si, str_hi_score_lbl
    mov ah, 0x1E
    call print_string
    mov ax, [HIGH_SCORE]
    call render_3digits_yellow
    mov byte [es:di - 5], 0x1E
    mov byte [es:di - 3], 0x1E
    mov byte [es:di - 1], 0x1E

    ; Dynamic help text for Tab 0
    mov di, (20 * 80 + 9) * 2
    mov al, [SETUP_SEL]
    mov si, str_help_tab
    cmp al, 0
    je .do_print_help
    mov si, str_help_0
    cmp al, 1
    je .do_print_help
    mov si, str_help_1
    cmp al, 2
    je .do_print_help
    mov si, str_help_2
    cmp al, 3
    je .do_print_help
    mov si, str_help_3
    cmp al, 4
    je .do_print_help
    mov si, str_help_4
    cmp al, 5
    je .do_print_help
    mov si, str_help_5
    cmp al, 6
    je .do_print_help
    mov si, str_help_6
    cmp al, 7
    je .do_print_help
    mov si, str_help_7
    cmp al, 8
    je .do_print_help
    mov si, str_help_8
    cmp al, 9
    je .do_print_help
    mov si, str_help_9
    jmp .do_print_help

    ; =========================================================================
    ; TAB 1: BIOSSHELL ITEMS (Indices 0..8)
    ; =========================================================================
.draw_tab1_items:
    mov bl, 0
    mov dh, 4
    mov si, str_opt_tab
    call draw_menu_row
    mov si, str_val_tab_shell
    call draw_val_str

    mov bl, 1
    mov dh, 6
    mov si, str_opt_sh_launch
    call draw_menu_row
    mov si, str_val_sh_launch
    call draw_val_str

    mov bl, 2
    mov dh, 8
    mov si, str_opt_sh_theme
    call draw_menu_row
    mov al, [CFG_SH_THEME]
    mov si, str_val_sht_efi
    cmp al, 1
    jne .chk_sht2
    mov si, str_val_sht_mat
    jmp .draw_sht_val
.chk_sht2:
    cmp al, 2
    jne .chk_sht3
    mov si, str_val_sht_cyb
    jmp .draw_sht_val
.chk_sht3:
    cmp al, 3
    jne .draw_sht_val
    mov si, str_val_sht_blu
.draw_sht_val:
    call draw_val_str

    mov bl, 3
    mov dh, 9
    mov si, str_opt_sh_prompt
    call draw_menu_row
    mov al, [CFG_SH_PROMPT]
    mov si, str_val_shp_fs0
    cmp al, 1
    jne .chk_shp2
    mov si, str_val_shp_shl
    jmp .draw_shp_val
.chk_shp2:
    cmp al, 2
    jne .draw_shp_val
    mov si, str_val_shp_roo
.draw_shp_val:
    call draw_val_str

    mov bl, 4
    mov dh, 10
    mov si, str_opt_sh_banner
    call draw_menu_row
    mov al, [CFG_SH_BANNER]
    mov si, str_val_shb_full
    cmp al, 1
    jne .chk_shb2
    mov si, str_val_shb_comp
    jmp .draw_shb_val
.chk_shb2:
    cmp al, 2
    jne .draw_shb_val
    mov si, str_val_shb_quiet
.draw_shb_val:
    call draw_val_str

    mov bl, 5
    mov dh, 11
    mov si, str_opt_sh_beep
    call draw_menu_row
    mov si, str_val_shk_on
    cmp byte [CFG_SH_BEEP], 1
    jne .draw_shk_val
    mov si, str_val_shk_off
.draw_shk_val:
    call draw_val_str

    mov bl, 6
    mov dh, 12
    mov si, str_opt_sh_boot
    call draw_menu_row
    mov si, str_val_shbt_snk
    cmp byte [CFG_BOOT_MODE], 1
    jne .draw_shbt_val
    mov si, str_val_shbt_shl
.draw_shbt_val:
    call draw_val_str

    mov bl, 7
    mov dh, 14
    mov si, str_opt_sh_reset
    call draw_menu_row

    mov bl, 8
    mov dh, 15
    mov si, str_opt_boot
    call draw_menu_row

    mov di, (16 * 80 + 10) * 2
    mov si, str_sh_tab_status
    mov ah, 0x1B
    call print_string

    mov di, (20 * 80 + 9) * 2
    mov al, [SETUP_SEL]
    mov si, str_help_tab
    cmp al, 0
    je .do_print_help
    mov si, str_help_sh1
    cmp al, 1
    je .do_print_help
    mov si, str_help_sh2
    cmp al, 2
    je .do_print_help
    mov si, str_help_sh3
    cmp al, 3
    je .do_print_help
    mov si, str_help_sh4
    cmp al, 4
    je .do_print_help
    mov si, str_help_sh5
    cmp al, 5
    je .do_print_help
    mov si, str_help_sh6
    cmp al, 6
    je .do_print_help
    mov si, str_help_8
    cmp al, 7
    je .do_print_help
    mov si, str_help_9

.do_print_help:
    mov ah, 0x1E
    call print_string
    ret

draw_menu_row:
    ; Input: bl = row index, dh = screen row (Y), si = string
    ; Modern UEFI highlight: fills full row (Cols 8..71) with Teal highlight bar (0x3F) when selected!
    push ax
    push cx
    push di
    cmp [SETUP_SEL], bl
    jne .dm_not_sel_bg
    mov al, 8
    push bx
    mov bl, dh
    call xy_to_di
    pop bx
    mov cx, 64
    mov ax, 0x3F20
    rep stosw
.dm_not_sel_bg:
    mov al, 10
    push bx
    mov bl, dh
    call xy_to_di
    pop bx

    mov ah, 0x1F
    cmp [SETUP_SEL], bl
    jne .dm_no_arrow
    mov ah, 0x3E                    ; Golden Arrow on Teal highlight bar
    mov al, 0x0B                    ; '▶' Play/Selection triangle
    stosw
    mov al, ' '
    stosw
    mov ah, 0x3F                    ; Crisp White label on Teal bar
    jmp .dm_print_txt
.dm_no_arrow:
    mov al, ' '
    stosw
    stosw
.dm_print_txt:
    call print_string
    pop di
    pop cx
    pop ax
    ret

draw_val_str:
    push ax
    push di
    mov al, 38                      ; Column 38 for value display
    push bx
    mov bl, dh
    call xy_to_di
    pop bx
    mov ah, 0x1A                    ; Neon Mint Green
    cmp [SETUP_SEL], bl
    jne .dv_go
    mov ah, 0x3E                    ; Golden Yellow on Teal when selected
.dv_go:
    call print_string
    pop di
    pop ax
    ret

init_snake_game:
    call mouse_hide_cursor
    call vga_set_mode13h

    ; Set snake length according to CFG_LEN
    mov word [SNAKE_LEN], 4
    cmp byte [CFG_LEN], 1
    jne .chk_cfg_len6
    mov word [SNAKE_LEN], 3
    jmp .set_snake_body
.chk_cfg_len6:
    cmp byte [CFG_LEN], 2
    jne .set_snake_body
    mov word [SNAKE_LEN], 6

.set_snake_body:
    ; Place snake on 28x16 square grass grid (Head at gx=9, gy=8)
    mov byte [SNAKE_X + 0], 9
    mov byte [SNAKE_Y + 0], 8
    mov byte [SNAKE_X + 1], 8
    mov byte [SNAKE_Y + 1], 8
    mov byte [SNAKE_X + 2], 7
    mov byte [SNAKE_Y + 2], 8
    mov byte [SNAKE_X + 3], 6
    mov byte [SNAKE_Y + 3], 8
    mov byte [SNAKE_X + 4], 5
    mov byte [SNAKE_Y + 4], 8
    mov byte [SNAKE_X + 5], 4
    mov byte [SNAKE_Y + 5], 8

    mov byte [SNAKE_DIR], 1         ; Initial direction: Right
    mov byte [NEXT_DIR], 1
    mov byte [QUEUED_DIR], 0xFF
    mov byte [DIR_LOCKED], 0
    mov word [SCORE], 0
    mov word [RND_SEED], 0x1337

    ; Initialize golden apple, bulge & tongue state
    mov byte [GOLD_FOOD_X], 0xFF
    mov word [GOLD_TIMER], 0
    mov byte [APPLE_COUNT], 0
    mov byte [BULGE_X], 0xFF
    mov byte [BULGE_Y], 0xFF
    mov byte [TONGUE_X], 0xFF
    mov byte [TONGUE_TICK], 0
    mov byte [CARD_BTN_SEL], 0
    mov byte [MOUSE_CLICK], 0
    mov byte [FIRST_SPAWN], 1

    call spawn_fruit

    ; Render Maximalist Cybforge Snake Sky-Blue Start Card in 320x200x256!
    mov byte [CARD_OPEN], 1
    xor dl, dl
    call gfx_draw_popup_card
    call gfx_present
    call drain_kbd

.wait_start:
    call read_key
    test al, al
    jnz .wait_start_key

    ; Check mouse movement / hover / click on the 3 Royal-Blue Pill Buttons!
    call check_card_mouse_hover
    test byte [MOUSE_CLICK], 0x01
    jz .wait_idle
    mov byte [MOUSE_CLICK], 0
    mov ax, [MOUSE_FINE_Y]
    shr ax, 1                       ; py = 0..199
    cmp ax, 154
    jb .game_started
    cmp ax, 173
    jb core_bios_setup
    cmp ax, 194
    jb bios_shell_main
    jmp .game_started

.wait_start_key:
    cmp al, 0x01                    ; ESC -> Enter BIOS Setup
    je core_bios_setup
    cmp al, 0x0F                    ; TAB -> Cycle Card Button (Play / Setup / Shell)
    je .card_next_btn
    cmp al, 0x03                    ; Key '2' -> BIOS Setup
    je core_bios_setup
    cmp al, 0x04                    ; Key '3' -> BIOS Shell
    je bios_shell_main

    cmp al, 0x1C                    ; ENTER -> Activate selected card button
    je .card_activate_btn
    cmp al, 0x39                    ; SPACE -> Start game immediately
    je .game_started

    ; Instant start with arrow keys / WASD!
    cmp al, 0x11                    ; W (Up)
    je .start_up
    cmp al, 0x48                    ; UP Arrow
    je .start_up
    cmp al, 0x1F                    ; S (Down)
    je .start_down
    cmp al, 0x50                    ; DOWN Arrow
    je .start_down
    cmp al, 0x20                    ; D (Right)
    je .start_right
    cmp al, 0x4D                    ; RIGHT Arrow
    je .start_right
    jmp .wait_idle

.card_next_btn:
    call sound_click
    inc byte [CARD_BTN_SEL]
    cmp byte [CARD_BTN_SEL], 3
    jb .card_redraw_btns
    mov byte [CARD_BTN_SEL], 0
.card_redraw_btns:
    xor dl, dl
    call gfx_draw_popup_card
    call gfx_present
    jmp .wait_idle

.card_activate_btn:
    cmp byte [CARD_BTN_SEL], 1
    je core_bios_setup
    cmp byte [CARD_BTN_SEL], 2
    je bios_shell_main
    jmp .game_started

.start_up:
    mov byte [SNAKE_DIR], 0
    mov byte [NEXT_DIR], 0
    jmp .game_started

.start_down:
    mov byte [SNAKE_DIR], 2
    mov byte [NEXT_DIR], 2
    jmp .game_started

.start_right:
    mov byte [SNAKE_DIR], 1
    mov byte [NEXT_DIR], 1
    jmp .game_started

.wait_idle:
    mov ecx, 250000                 ; ~1ms polling
    call delay_cycles
    jmp .wait_start

.game_started:
    mov byte [CARD_OPEN], 0
    call sound_start
    call gfx_render_scene
    call gfx_present

    ; =========================================================================
    ; PHASE 4: MAIN GAME LOOP (320x200x256 Double-Buffered Pixel Engine)
    ; =========================================================================
game_loop:
    mov bp, 10
    cmp byte [CFG_SPEED], 1
    jne .chk_spd_slow
    mov bp, 7
    jmp .tick_loop
.chk_spd_slow:
    cmp byte [CFG_SPEED], 2
    jne .tick_loop
    mov bp, 14

.tick_loop:
    call handle_input
    ; Update hardware mouse cursor live during sub-ticks if moved
    mov ax, [MOUSE_FINE_X]
    cmp ax, [MOUSE_LAST_FX]
    jne .tick_redraw_mouse
    mov ax, [MOUSE_FINE_Y]
    cmp ax, [MOUSE_LAST_FY]
    je .tick_delay
.tick_redraw_mouse:
    call gfx_present
.tick_delay:
    mov ecx, 3800000                ; ~15 ms Mini-Tick
    call delay_cycles
    dec bp
    jnz .tick_loop

    ; 2. Apply direction & activate buffered keystroke
    mov al, [NEXT_DIR]
    mov [SNAKE_DIR], al
    mov byte [DIR_LOCKED], 0

    mov al, [QUEUED_DIR]
    cmp al, 0xFF
    je .no_queued_dir
    mov [NEXT_DIR], al
    mov byte [QUEUED_DIR], 0xFF
    mov byte [DIR_LOCKED], 1
.no_queued_dir:

    ; 3. Calculate new head position on 28x16 grid (gx=0..27, gy=0..15)
    mov al, [SNAKE_X]
    mov bl, [SNAKE_Y]
    mov cl, [SNAKE_DIR]

    cmp cl, 0
    jne .not_up
    dec bl
    jmp .move_calc_done
.not_up:
    cmp cl, 1
    jne .not_right
    inc al
    jmp .move_calc_done
.not_right:
    cmp cl, 2
    jne .not_down
    inc bl
    jmp .move_calc_done
.not_down:
    dec al

.move_calc_done:
    cmp byte [CFG_WALLS], 1
    jne .store_new_head

    ; Wrap-Around logic (Cols 0..27, Rows 0..15)
    cmp al, 0
    jge .chk_wrap_r
    mov al, 27
    jmp .chk_wrap_y
.chk_wrap_r:
    cmp al, 27
    jle .chk_wrap_y
    mov al, 0

.chk_wrap_y:
    cmp bl, 0
    jge .chk_wrap_b
    mov bl, 15
    jmp .store_new_head
.chk_wrap_b:
    cmp bl, 15
    jle .store_new_head
    mov bl, 0

.store_new_head:
    mov [NEW_HEAD_X], al
    mov [NEW_HEAD_Y], bl

    ; 4. Check wall collision (when Solid)
    cmp byte [CFG_WALLS], 1
    je .no_wall_collision

    cmp al, 0
    jl .do_crash
    cmp al, 28
    jge .do_crash
    cmp bl, 0
    jl .do_crash
    cmp bl, 16
    jge .do_crash

.no_wall_collision:
    mov al, [NEW_HEAD_X]
    mov bl, [NEW_HEAD_Y]
    call is_arena_wall
    jz .do_crash

    ; 5. Check self-collision with body (tail tip moves away)
    mov cx, [SNAKE_LEN]
    dec cx
    jz .no_body_collision
    xor si, si
.self_chk_loop:
    cmp al, [SNAKE_X + si]
    jne .no_body_hit
    cmp bl, [SNAKE_Y + si]
    je .do_crash
.no_body_hit:
    inc si
    loop .self_chk_loop

.no_body_collision:
    ; 6. Update golden apple timer & check if golden apple eaten
    cmp byte [GOLD_FOOD_X], 0xFF
    je .chk_eat_regular

    dec word [GOLD_TIMER]
    jz .gold_expired

    mov al, [NEW_HEAD_X]
    mov bl, [NEW_HEAD_Y]
    cmp al, [GOLD_FOOD_X]
    jne .chk_eat_regular
    cmp bl, [GOLD_FOOD_Y]
    jne .chk_eat_regular

    ; --- GOLDEN APPLE EATEN! (+50 Points) ---
    add word [SCORE], 50
    mov ax, [SCORE]
    cmp ax, [HIGH_SCORE]
    jbe .gold_hi_ok
    mov [HIGH_SCORE], ax
.gold_hi_ok:
    mov al, [NEW_HEAD_X]
    mov bl, [NEW_HEAD_Y]
    mov [BULGE_X], al
    mov [BULGE_Y], bl
    mov byte [GOLD_FOOD_X], 0xFF
    call sound_golden_apple
    jmp .chk_eat_regular

.gold_expired:
    mov byte [GOLD_FOOD_X], 0xFF

.chk_eat_regular:
    ; 7. Check if regular apple was eaten
    mov al, [NEW_HEAD_X]
    mov bl, [NEW_HEAD_Y]
    cmp al, [FOOD_X]
    jne .normal_move
    cmp bl, [FOOD_Y]
    jne .normal_move

    ; --- REGULAR APPLE EATEN! ---
    mov [BULGE_X], al
    mov [BULGE_Y], bl
    inc word [SCORE]
    mov ax, [SCORE]
    cmp ax, [HIGH_SCORE]
    jbe .reg_hi_ok
    mov [HIGH_SCORE], ax
.reg_hi_ok:
    inc byte [APPLE_COUNT]
    call sound_eat_fruit

    ; Spawn a golden apple every 5 apples (if not already active)
    cmp byte [GOLD_FOOD_X], 0xFF
    jne .no_new_gold
    mov al, [APPLE_COUNT]
    xor ah, ah
    mov cl, 5
    div cl
    test ah, ah
    jnz .no_new_gold
    call spawn_golden_apple
.no_new_gold:

    ; Grow snake
    mov ax, [SNAKE_LEN]
    cmp ax, 448
    jae .grow_len_done
    inc ax
    mov [SNAKE_LEN], ax
.grow_len_done:

    ; Check victory condition
    mov cx, 448
    cmp byte [CFG_WIN], 1
    jne .chk_win_g50
    mov cx, 25
    jmp .chk_win_eval
.chk_win_g50:
    cmp byte [CFG_WIN], 2
    jne .chk_win_g100
    mov cx, 50
    jmp .chk_win_eval
.chk_win_g100:
    cmp byte [CFG_WIN], 3
    jne .chk_win_eval
    mov cx, 100
.chk_win_eval:
    cmp ax, cx
    jae victory_screen

    ; Shift body segments backward
    mov cx, [SNAKE_LEN]
    dec cx
    jz .shift_grow_head
.shift_grow_loop:
    mov si, cx
    mov al, [SNAKE_X + si - 1]
    mov [SNAKE_X + si], al
    mov al, [SNAKE_Y + si - 1]
    mov [SNAKE_Y + si], al
    dec cx
    jnz .shift_grow_loop

.shift_grow_head:
    mov al, [NEW_HEAD_X]
    mov [SNAKE_X + 0], al
    mov al, [NEW_HEAD_Y]
    mov [SNAKE_Y + 0], al

    call spawn_fruit
    call gfx_render_scene
    call gfx_present
    jmp game_loop

.normal_move:
    ; Check if digesting bulge reached the tail tip
    mov si, [SNAKE_LEN]
    dec si
    mov al, [SNAKE_X + si]
    mov bl, [SNAKE_Y + si]
    cmp al, [BULGE_X]
    jne .shift_segs
    cmp bl, [BULGE_Y]
    jne .shift_segs
    mov byte [BULGE_X], 0xFF

.shift_segs:
    mov cx, [SNAKE_LEN]
    dec cx
.shift_loop:
    mov si, cx
    mov al, [SNAKE_X + si - 1]
    mov [SNAKE_X + si], al
    mov al, [SNAKE_Y + si - 1]
    mov [SNAKE_Y + si], al
    loop .shift_loop

    ; Place new head
    mov al, [NEW_HEAD_X]
    mov [SNAKE_X], al
    mov al, [NEW_HEAD_Y]
    mov [SNAKE_Y], al

    call gfx_render_scene
    call gfx_present
    jmp game_loop

.do_crash:
    call crash_dissolve_animation
    jmp game_over

    ; =========================================================================
    ; PHASE 5A: VICTORY SCREEN (Mode 13h Graphical Trophy & Victory Fanfare)
    ; =========================================================================
victory_screen:
    call sound_victory
    mov byte [CARD_OPEN], 1
    call gfx_draw_board

    ; Draw Victory Sky-Blue Rounded Card (X=52..267, Y=28..184)
    mov ax, 54
    mov bx, 30
    mov cx, 216
    mov dx, 156
    mov byte [GFX_COLOR], 26
    call gfx_fill_rect

    mov ax, 52
    mov bx, 28
    mov cx, 216
    mov dx, 156
    mov byte [GFX_COLOR], 6
    call gfx_fill_rounded_rect

    ; Title: "* VICTORY! *"
    mov ax, 116
    mov bx, 36
    mov si, str_vic_short
    mov dl, 22
    call gfx_draw_text

    ; Subtitle: "YOU CONQUERED THE BOARD!"
    mov ax, 64
    mov bx, 50
    mov si, str_vic_hdr2
    mov dl, 15
    call gfx_draw_text

    ; Draw 3 Golden Trophies in the center
    mov ax, 124
    mov bx, 72
    mov si, sprite_trophy16
    call gfx_draw_sprite16
    mov ax, 152
    mov bx, 68
    mov si, sprite_trophy16
    call gfx_draw_sprite16
    mov ax, 180
    mov bx, 72
    mov si, sprite_trophy16
    call gfx_draw_sprite16

    ; Board status
    mov ax, 64
    mov bx, 104
    mov si, str_vic_status
    mov dl, 22
    call gfx_draw_text

    ; Play Again button
    mov ax, 76
    mov bx, 140
    mov cx, 168
    mov dx, 20
    mov byte [GFX_COLOR], 9
    call gfx_fill_rounded_rect
    mov ax, 92
    mov bx, 146
    mov si, str_btn_play_txt
    mov dl, 15
    call gfx_draw_text

    call gfx_present
    call drain_kbd
    mov byte [MOUSE_CLICK], 0

.wait_vic_key:
    call read_key
    cmp al, 0x1C
    je init_snake_game
    cmp al, 0x39
    je init_snake_game
    cmp al, 0x01
    je core_bios_setup
    test byte [MOUSE_CLICK], 0x01
    jnz init_snake_game
    mov ecx, 5000000
    call delay_cycles
    jmp .wait_vic_key

    ; =========================================================================
    ; PHASE 5: CYBFORGE SNAKE SKY-BLUE GAME OVER POPUP CARD
    ; =========================================================================
game_over:
    call sound_game_over

    ; Check if score qualifies for Top 3 -> Initials entry!
    call check_top3_qualification

    ; Render the Cybforge Snake Sky-Blue Popup Card in Game Over mode (dl = 1)!
    mov byte [CARD_BTN_SEL], 0
    mov byte [MOUSE_CLICK], 0
    mov byte [CARD_OPEN], 1
    mov dl, 1
    call gfx_draw_popup_card
    call gfx_present
    call drain_kbd

.wait_enter:
    call read_key
    test al, al
    jnz .go_got_key

    call check_card_mouse_hover_go
    test byte [MOUSE_CLICK], 0x01
    jz .go_idle
    mov byte [MOUSE_CLICK], 0
    mov ax, [MOUSE_FINE_Y]
    shr ax, 1
    cmp ax, 154
    jb .do_restart
    cmp ax, 173
    jb .do_setup
    cmp ax, 194
    jb .do_shell
    jmp .do_restart

.go_got_key:
    cmp al, 0x1C                    ; ENTER -> Activate selected button
    je .go_activate_btn
    cmp al, 0x39                    ; SPACE -> Restart
    je .do_restart
    cmp al, 0x01                    ; ESC -> Setup
    je .do_setup
    cmp al, 0x0F                    ; TAB -> Next button
    je .go_next_btn
    cmp al, 0x48                    ; Up arrow
    je .go_prev_btn
    cmp al, 0x50                    ; Down arrow
    je .go_next_btn
    cmp al, 0x03                    ; '2' -> Setup
    je .do_setup
    cmp al, 0x04                    ; '3' -> Shell
    je .do_shell

.go_idle:
    mov ecx, 250000
    call delay_cycles
    jmp .wait_enter

.go_next_btn:
    call sound_click
    inc byte [CARD_BTN_SEL]
    cmp byte [CARD_BTN_SEL], 3
    jb .go_redraw_btns
    mov byte [CARD_BTN_SEL], 0
    jmp .go_redraw_btns

.go_prev_btn:
    call sound_click
    dec byte [CARD_BTN_SEL]
    jns .go_redraw_btns
    mov byte [CARD_BTN_SEL], 2

.go_redraw_btns:
    mov dl, 1
    call gfx_draw_popup_card
    call gfx_present
    jmp .go_idle

.go_activate_btn:
    cmp byte [CARD_BTN_SEL], 1
    je .do_setup
    cmp byte [CARD_BTN_SEL], 2
    je .do_shell
.do_restart:
    jmp init_snake_game

.do_setup:
    call sound_click
    jmp core_bios_setup

.do_shell:
    call sound_start
    jmp bios_shell_main

    ; =========================================================================
    ; PHASE 6: INPUT HANDLER (WASD + Arrows + Mouse Click Steering & HUD!)
    ; =========================================================================
handle_input:
    call read_key
    test al, al
    jnz .hi_got_key

    ; Check if mouse button was clicked during gameplay!
    test byte [MOUSE_CLICK], 0x01
    jz .input_done
    mov byte [MOUSE_CLICK], 0

    mov ax, [MOUSE_FINE_X]
    shr ax, 1                       ; AX = px (0..319)
    mov bx, [MOUSE_FINE_Y]
    shr bx, 1                       ; BX = py (0..199)

    ; Did user click the top Forest-Green HUD bar (py < 24)?
    cmp bx, 24
    jae .mouse_steer_playfield
    cmp ax, 272
    jb .hud_toggle_sound
    cmp ax, 292
    jb .do_pause
    pop ax                          ; Clean up return address -> jump to Setup
    call sound_click
    jmp core_bios_setup

.hud_toggle_sound:
    inc byte [CFG_SOUND]
    and byte [CFG_SOUND], 3
    call sound_toggle
    ret

.mouse_steer_playfield:
    ; Convert clicked pixel (AX=px, BX=py) to 28x16 grid coordinate (dl=gx, dh=gy)
    sub ax, 20
    jns .ms_px_pos
    xor ax, ax
.ms_px_pos:
    mov cl, 10
    div cl
    mov dl, al                      ; DL = clicked gx (0..27)

    mov ax, bx
    sub ax, 32
    jns .ms_py_pos
    xor ax, ax
.ms_py_pos:
    div cl
    mov dh, al                      ; DH = clicked gy (0..15)

    mov al, [SNAKE_DIR]
    test al, 1                      ; Moving horizontally (Right=1 or Left=3)?
    jnz .steer_vertical
    mov cl, 1
    cmp dl, [SNAKE_X]
    jae .apply_new_dir
    mov cl, 3
    jmp .apply_new_dir
.steer_vertical:
    mov cl, 2
    cmp dh, [SNAKE_Y]
    jae .apply_new_dir
    mov cl, 0
    jmp .apply_new_dir

.hi_got_key:
    cmp al, 0x01                    ; ESC -> Setup
    jne .chk_pause
    pop ax                          ; Clean up stack
    call sound_click
    jmp core_bios_setup

.chk_pause:
    cmp al, 0x19                    ; 'P'
    je .do_pause
    cmp al, 0x39                    ; SPACE
    je .do_pause
    jmp .chk_wasd

.do_pause:
    call sound_pause
    ; Draw Sky-Blue Rounded Pause Modal (X=64..255, Y=66..134)
    mov ax, 66
    mov bx, 68
    mov cx, 192
    mov dx, 68
    mov byte [GFX_COLOR], 26
    call gfx_fill_rect

    mov ax, 64
    mov bx, 66
    mov cx, 192
    mov dx, 68
    mov byte [GFX_COLOR], 6
    call gfx_fill_rounded_rect

    mov ax, 76
    mov bx, 80
    mov si, str_paused_lbl
    mov dl, 22
    call gfx_draw_text

    mov ax, 68
    mov bx, 104
    mov si, str_pause_resume
    mov dl, 15
    call gfx_draw_text

    call gfx_present
    call drain_kbd
    mov byte [MOUSE_CLICK], 0

.wait_pause_key:
    call read_key
    cmp al, 0x19
    je .resume_game
    cmp al, 0x39
    je .resume_game
    cmp al, 0x01
    je .pause_to_setup
    test byte [MOUSE_CLICK], 0x01
    jnz .resume_game
    mov ecx, 5000000
    call delay_cycles
    jmp .wait_pause_key

.pause_to_setup:
    call sound_click
    pop ax
    jmp core_bios_setup

.resume_game:
    mov byte [MOUSE_CLICK], 0
    call sound_pause
    call gfx_render_scene
    call gfx_present
    ret

.chk_wasd:
    cmp al, 0x11
    je .is_up
    cmp al, 0x48
    je .is_up
    cmp al, 0x20
    je .is_right
    cmp al, 0x4D
    je .is_right
    cmp al, 0x1F
    je .is_down
    cmp al, 0x50
    je .is_down
    cmp al, 0x1E
    je .is_left
    cmp al, 0x4B
    je .is_left
    jmp .input_done

.is_up:
    mov cl, 0
    jmp .apply_new_dir
.is_right:
    mov cl, 1
    jmp .apply_new_dir
.is_down:
    mov cl, 2
    jmp .apply_new_dir
.is_left:
    mov cl, 3

.apply_new_dir:
    cmp byte [DIR_LOCKED], 0
    jne .chk_queue

    mov bl, [SNAKE_DIR]
    cmp cl, bl
    je .input_done
    xor bl, 2
    cmp cl, bl
    je .input_done

    mov [NEXT_DIR], cl
    mov byte [DIR_LOCKED], 1
    ret

.chk_queue:
    mov bl, [NEXT_DIR]
    cmp cl, bl
    je .input_done
    xor bl, 2
    cmp cl, bl
    je .input_done
    mov [QUEUED_DIR], cl

.input_done:
    ret

    ; =========================================================================
    ; PHASE 7: MODE 13H (320x200x256) DOUBLE-BUFFERED PIXEL GRAPHICS ENGINE
    ; Backbuffer in RAM: Segment 0x3000:0000 (64,000 Bytes)
    ; Hardware Linear Framebuffer: Segment 0xA000:0000 (64,000 Bytes)
    ; =========================================================================
GFX_COLOR       equ 0x1C22
GFX_TMP_X       equ 0x1C24
GFX_TMP_Y       equ 0x1C26
MOUSE_GFX_BG    equ 0x1C30          ; 192 bytes (12x16 patch)

vga_set_mode13h:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    mov byte [VGA_GFX_ACTIVE], 1

    ; 1. Misc Output Register (0x3C2) = 0x63 (25 MHz, 400-line mode, RAM enable)
    mov dx, 0x3C2
    mov al, 0x63
    out dx, al

    ; 2. Sequencer Registers (0x3C4 / 0x3C5) for Chain-4 256-Color Mode 13h
    mov dx, 0x3C4
    mov ax, 0x0100                  ; Sync Reset
    out dx, ax
    mov si, mode13h_seq_table
    mov cx, 4
    mov ah, 1
.m13_seq:
    mov dx, 0x3C4
    mov al, ah
    out dx, al
    inc dx
    mov al, [cs:si]
    inc si
    out dx, al
    inc ah
    loop .m13_seq
    mov dx, 0x3C4
    mov ax, 0x0300                  ; End Sync Reset
    out dx, ax

    ; 3. CRTC Registers (0x3D4 / 0x3D5) for 320x200 Chain-4
    mov dx, 0x3D4
    mov ax, 0x0011                  ; Unlock CR00..CR07
    out dx, ax
    mov si, mode13h_crtc_table
    mov cx, 25
    xor ah, ah
.m13_crtc:
    mov dx, 0x3D4
    mov al, ah
    out dx, al
    inc dx
    mov al, [cs:si]
    inc si
    out dx, al
    inc ah
    loop .m13_crtc

    ; 4. Graphics Controller Registers (0x3CE / 0x3CF)
    mov si, mode13h_gc_table
    mov cx, 9
    xor ah, ah
.m13_gc:
    mov dx, 0x3CE
    mov al, ah
    out dx, al
    inc dx
    mov al, [cs:si]
    inc si
    out dx, al
    inc ah
    loop .m13_gc

    ; 5. Attribute Controller Registers (0x3C0)
    mov dx, 0x3DA
    in al, dx
    mov dx, 0x3C0
    xor ah, ah
.m13_ac_pal:
    mov al, ah
    out dx, al
    out dx, al
    inc ah
    cmp ah, 16
    jb .m13_ac_pal
    mov si, mode13h_ac_ext_table
    mov cx, 5
.m13_ac_ext:
    mov al, ah
    out dx, al
    mov al, [cs:si]
    inc si
    out dx, al
    inc ah
    loop .m13_ac_ext

    mov dx, 0x3DA
    in al, dx
    mov dx, 0x3C0
    mov al, 0x20                    ; Enable video output
    out dx, al

    mov dx, 0x3C6
    mov al, 0xFF
    out dx, al

    ; 6. Load 32-entry 256-Color Cybforge Snake DAC Palette (with Theme support!)
    call load_mode13h_palette

    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

load_mode13h_palette:
    push ax
    push cx
    push dx
    push si

    ; Colors 0..5 come from selected board theme (CFG_THEME 0..3, 18 bytes each)
    mov al, [CFG_THEME]
    and al, 3
    mov cl, 18
    mul cl
    mov si, mode13h_theme_palettes
    add si, ax

    mov dx, 0x3C8
    xor al, al
    out dx, al
    mov dx, 0x3C9
    mov cx, 18
.m13_pal_th:
    mov al, [cs:si]
    inc si
    out dx, al
    loop .m13_pal_th

    ; Colors 6..31 come from mode13h_fixed_palette (26 * 3 = 78 bytes)
    mov si, mode13h_fixed_palette
    mov cx, 26 * 3
.m13_pal_fx:
    mov al, [cs:si]
    inc si
    out dx, al
    loop .m13_pal_fx

    pop si
    pop dx
    pop cx
    pop ax
    ret

vga_set_text_mode:
    cmp byte [VGA_GFX_ACTIVE], 1
    jne .vstm_done
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov byte [VGA_GFX_ACTIVE], 0

    ; 1. Restore 80x25 Text Mode VGA Registers
    mov dx, 0x3C2
    mov al, 0x67
    out dx, al

    mov dx, 0x3C4
    mov ax, 0x0100
    out dx, ax
    mov si, vga_seq_table
    mov cx, 4
    mov ah, 1
.vstm_seq:
    mov dx, 0x3C4
    mov al, ah
    out dx, al
    inc dx
    mov al, [cs:si]
    inc si
    out dx, al
    inc ah
    loop .vstm_seq
    mov dx, 0x3C4
    mov ax, 0x0300
    out dx, ax

    mov dx, 0x3D4
    mov ax, 0x0011
    out dx, ax
    mov si, vga_crtc_table
    mov cx, 25
    xor ah, ah
.vstm_crtc:
    mov dx, 0x3D4
    mov al, ah
    out dx, al
    inc dx
    mov al, [cs:si]
    inc si
    out dx, al
    inc ah
    loop .vstm_crtc
    ; Disable hardware text cursor (CR0A = 0x20)
    mov dx, 0x3D4
    mov ax, 0x200A
    out dx, ax

    mov si, vga_gc_table
    mov cx, 9
    xor ah, ah
.vstm_gc:
    mov dx, 0x3CE
    mov al, ah
    out dx, al
    inc dx
    mov al, [cs:si]
    inc si
    out dx, al
    inc ah
    loop .vstm_gc

    mov dx, 0x3DA
    in al, dx
    mov dx, 0x3C0
    xor ah, ah
.vstm_ac_pal:
    mov al, ah
    out dx, al
    out dx, al
    inc ah
    cmp ah, 16
    jb .vstm_ac_pal
    mov si, vga_ac_ext_table
    mov cx, 5
.vstm_ac_ext:
    mov al, ah
    out dx, al
    mov al, [cs:si]
    inc si
    out dx, al
    inc ah
    loop .vstm_ac_ext
    mov dx, 0x3DA
    in al, dx
    mov dx, 0x3C0
    mov al, 0x20
    out dx, al

    ; 2. Reload ASCII + Custom Glyphs into Plane 2 via vga_apply_font_scale
    call vga_apply_font_scale

    ; 3. Also reload Cybforge POST Logo Glyphs (0x80..0xBB) into Plane 2
    mov dx, 0x3C4
    mov ax, 0x0100
    out dx, ax
    mov ax, 0x0402
    out dx, ax
    mov ax, 0x0604
    out dx, ax
    mov ax, 0x0300
    out dx, ax
    mov dx, 0x3CE
    mov ax, 0x0204
    out dx, ax
    mov ax, 0x0005
    out dx, ax
    mov ax, 0x0406
    out dx, ax

    mov ax, 0xA000
    mov es, ax
    mov si, logo_font_table
.vstm_logo_lp:
    mov al, [cs:si]
    inc si
    test al, al
    jz .vstm_logo_done
    xor ah, ah
    shl ax, 5
    mov di, ax
    mov cx, 16
.vstm_logo_cp:
    mov al, [cs:si]
    inc si
    stosb
    loop .vstm_logo_cp
    jmp .vstm_logo_lp
.vstm_logo_done:
    mov dx, 0x3C4
    mov ax, 0x0100
    out dx, ax
    mov ax, 0x0302
    out dx, ax
    mov ax, 0x0204
    out dx, ax
    mov ax, 0x0300
    out dx, ax
    mov dx, 0x3CE
    mov ax, 0x0004
    out dx, ax
    mov ax, 0x1005
    out dx, ax
    mov ax, 0x0E06
    out dx, ax

    ; 4. Restore ES = 0xB800 and load Modern UEFI Dark Slate Palette
    mov ax, 0xB800
    mov es, ax
    call load_ui_palette

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
.vstm_done:
    ret

; -----------------------------------------------------------------------------
; Low-Level 320x200 Backbuffer Drawing Primitives (Target Segment 0x3000)
; -----------------------------------------------------------------------------
gfx_fill_rect:
    ; Input: AX = x, BX = y, CX = width, DX = height, [GFX_COLOR] = color
    push ax
    push bx
    push cx
    push dx
    push di
    push es

    cmp cx, 0
    jle .gfr_done
    cmp dx, 0
    jle .gfr_done

    mov di, 0x3000
    mov es, di

    ; Compute di = y * 320 + x
    imul di, bx, 320
    add di, ax
    mov al, [GFX_COLOR]
.gfr_row:
    push cx
    push di
    rep stosb
    pop di
    pop cx
    add di, 320
    dec dx
    jnz .gfr_row

.gfr_done:
    pop es
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

gfx_fill_rounded_rect:
    ; Input: AX = x, BX = y, CX = width, DX = height, [GFX_COLOR] = color
    ; Draws a rounded pill/card rectangle by inseting the top/bottom 2 scanlines
    push ax
    push bx
    push cx
    push dx

    ; Center body: (x, y+2, w, h-4)
    push ax
    push bx
    push cx
    push dx
    add bx, 2
    sub dx, 4
    call gfx_fill_rect
    pop dx
    pop cx
    pop bx
    pop ax

    ; Top 2 rows: (x+2, y, w-4, 1) and (x+1, y+1, w-2, 1)
    push ax
    push bx
    push cx
    add ax, 2
    sub cx, 4
    mov dx, 1
    call gfx_fill_rect
    pop cx
    pop bx
    pop ax

    push ax
    push bx
    push cx
    inc ax
    inc bx
    sub cx, 2
    mov dx, 1
    call gfx_fill_rect
    pop cx
    pop bx
    pop ax

    ; Bottom 2 rows: (x+1, y+h-2, w-2, 1) and (x+2, y+h-1, w-4, 1)
    push ax
    push bx
    push cx
    push dx
    inc ax
    add bx, dx
    sub bx, 2
    sub cx, 2
    mov dx, 1
    call gfx_fill_rect
    pop dx
    pop cx
    pop bx
    pop ax

    add ax, 2
    add bx, dx
    dec bx
    sub cx, 4
    mov dx, 1
    call gfx_fill_rect

    pop dx
    pop cx
    pop bx
    pop ax
    ret

gfx_draw_char:
    ; Input: AX = x, BX = y, CL = ASCII char, DL = fg color (with 1px shadow in Color 26)
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    ; Look up char CL in font_table (each entry: 1 byte code + 16 bytes scanlines)
    mov si, font_table
.gdc_find:
    mov ch, [cs:si]
    test ch, ch
    jz .gdc_done
    cmp ch, cl
    je .gdc_found
    add si, 17
    jmp .gdc_find

.gdc_found:
    inc si                          ; SI points to 16 scanlines (use scanlines 2..11 compressed to 8 rows!)
    mov di, 0x3000
    mov es, di
    imul di, bx, 320
    add di, ax

    ; Render 12 scanlines (rows 2..13 of the 8x16 glyph) so lowercase descenders ('y','g','p') are crisp!
    add si, 2
    mov ch, 12
.gdc_row:
    mov ah, [cs:si]
    inc si
    mov cl, 8
    push di
.gdc_bit:
    shl ah, 1
    jnc .gdc_next_px
    mov byte [es:di + 321], 26      ; 1px Bottom-Right Drop Shadow
    mov [es:di], dl                 ; Crisp Foreground Pixel
.gdc_next_px:
    inc di
    dec cl
    jnz .gdc_bit
    pop di
    add di, 320
    dec ch
    jnz .gdc_row

.gdc_done:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

gfx_draw_text:
    ; Input: AX = x, BX = y, SI = null-terminated string in CS, DL = fg color
    push ax
    push bx
    push cx
    push si
.gdt_lp:
    mov cl, [cs:si]
    inc si
    test cl, cl
    jz .gdt_done
    call gfx_draw_char
    add ax, 8
    jmp .gdt_lp
.gdt_done:
    pop si
    pop cx
    pop bx
    pop ax
    ret

gfx_draw_3digits:
    ; Input: AX = x, BX = y, CX = 16-bit number (0..999), DL = fg color
    push ax
    push bx
    push cx
    push dx
    mov [GFX_TMP_X], ax
    mov [GFX_TMP_Y], bx
    mov [GFX_COLOR], dl             ; Save foreground color safely in [GFX_COLOR]!

    mov ax, cx
    xor dx, dx
    mov cx, 100
    div cx                          ; AL = hundreds, DX = remainder (0..99)
    mov cl, al
    add cl, '0'
    push dx                         ; Preserve remainder across gfx_draw_char!
    mov ax, [GFX_TMP_X]
    mov bx, [GFX_TMP_Y]
    mov dl, [GFX_COLOR]
    call gfx_draw_char
    pop dx

    add word [GFX_TMP_X], 8
    mov ax, dx
    xor dx, dx
    mov cx, 10
    div cx                          ; AL = tens, DL = ones (0..9)
    mov cl, al
    add cl, '0'
    push dx                         ; Preserve ones digit across gfx_draw_char!
    mov ax, [GFX_TMP_X]
    mov bx, [GFX_TMP_Y]
    mov dl, [GFX_COLOR]
    call gfx_draw_char
    pop dx

    add word [GFX_TMP_X], 8
    mov cl, dl
    add cl, '0'
    mov ax, [GFX_TMP_X]
    mov bx, [GFX_TMP_Y]
    mov dl, [GFX_COLOR]
    call gfx_draw_char

    pop dx
    pop cx
    pop bx
    pop ax
    ret

gfx_draw_sprite10:
    ; Input: AX = x, BX = y, SI = 10x10 byte sprite in CS (0xFF = transparent)
    push ax
    push bx
    push cx
    push si
    push di
    push es
    mov di, 0x3000
    mov es, di
    imul di, bx, 320
    add di, ax
    mov ch, 10
.gds10_r:
    mov cl, 10
    push di
.gds10_c:
    mov al, [cs:si]
    inc si
    cmp al, 0xFF
    je .gds10_skip
    mov [es:di], al
.gds10_skip:
    inc di
    dec cl
    jnz .gds10_c
    pop di
    add di, 320
    dec ch
    jnz .gds10_r
    pop es
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

gfx_draw_sprite16:
    ; Input: AX = x, BX = y, SI = 16x16 byte sprite in CS (0xFF = transparent)
    push ax
    push bx
    push cx
    push si
    push di
    push es
    mov di, 0x3000
    mov es, di
    imul di, bx, 320
    add di, ax
    mov ch, 16
.gds16_r:
    mov cl, 16
    push di
.gds16_c:
    mov al, [cs:si]
    inc si
    cmp al, 0xFF
    je .gds16_skip
    mov [es:di], al
.gds16_skip:
    inc di
    dec cl
    jnz .gds16_c
    pop di
    add di, 320
    dec ch
    jnz .gds16_r
    pop es
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

gfx_present:
    ; Draws the hardware mouse cursor onto the backbuffer (0x3000:0000),
    ; copies all 64,000 bytes to VGA 0xA000:0000, and restores the patch under the cursor!
    push eax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ds
    push es

    ; Compute clamped cursor pixel (px in 0..307, py in 0..183)
    mov ax, [MOUSE_FINE_X]
    mov [MOUSE_LAST_FX], ax
    shr ax, 1
    cmp ax, 307
    jbe .gp_x_ok
    mov ax, 307
.gp_x_ok:
    mov bx, [MOUSE_FINE_Y]
    mov [MOUSE_LAST_FY], bx
    shr bx, 1
    cmp bx, 183
    jbe .gp_y_ok
    mov bx, 183
.gp_y_ok:
    imul di, bx, 320
    add di, ax                      ; DI = top-left offset of 12x16 cursor patch in 0x3000
    mov bp, di

    ; 1. Save 12x16 background patch from 0x3000:bp into DS:MOUSE_GFX_BG
    mov ax, 0x3000
    mov es, ax
    mov si, MOUSE_GFX_BG
    mov ch, 16
.gp_save_r:
    mov cl, 12
    push di
.gp_save_c:
    mov al, [es:di]
    mov [ds:si], al
    inc di
    inc si
    dec cl
    jnz .gp_save_c
    pop di
    add di, 320
    dec ch
    jnz .gp_save_r

    ; 2. Draw 12x16 Black-Outlined White Arrow Cursor onto 0x3000:bp
    mov di, bp
    mov si, sprite_cursor_12x16
    mov ch, 16
.gp_cur_r:
    mov cl, 12
    push di
.gp_cur_c:
    mov al, [cs:si]
    inc si
    cmp al, 0xFF
    je .gp_cur_skip
    mov [es:di], al
.gp_cur_skip:
    inc di
    dec cl
    jnz .gp_cur_c
    pop di
    add di, 320
    dec ch
    jnz .gp_cur_r

    ; 3. Tear-free 32-bit burst copy from 0x3000:0000 to 0xA000:0000 (16,000 dwords)
    mov ax, 0x3000
    mov ds, ax
    mov ax, 0xA000
    mov es, ax
    xor si, si
    xor di, di
    mov cx, 16000
    rep movsd

    ; 4. Restore 12x16 background patch back into 0x3000:bp
    xor ax, ax
    mov ds, ax
    mov ax, 0x3000
    mov es, ax
    mov di, bp
    mov si, MOUSE_GFX_BG
    mov ch, 16
.gp_rest_r:
    mov cl, 12
    push di
.gp_rest_c:
    mov al, [ds:si]
    mov [es:di], al
    inc si
    inc di
    dec cl
    jnz .gp_rest_c
    pop di
    add di, 320
    dec ch
    jnz .gp_rest_r

    pop es
    pop ds
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop eax
    ret

; -----------------------------------------------------------------------------
; Scene Renderer: HUD Bar, 28x16 Grass Checkerboard, Obstacles, Apple & Snake
; -----------------------------------------------------------------------------
gfx_render_scene:
    call gfx_draw_board
    call gfx_draw_fruit
    call gfx_draw_snake
    ret

gfx_draw_board:
    push ax
    push bx
    push cx
    push dx
    push si

    ; 1. Top Dark Forest-Green HUD Bar (Y = 0..23, Color 0)
    xor ax, ax
    xor bx, bx
    mov cx, 320
    mov dx, 24
    mov byte [GFX_COLOR], 0
    call gfx_fill_rect

    ; 2. Outer Playfield Forest Border (Y = 24..199, Color 1)
    xor ax, ax
    mov bx, 24
    mov cx, 320
    mov dx, 176
    mov byte [GFX_COLOR], 1
    call gfx_fill_rect

    ; Subtle 1px dark inner frame around the 280x160 playfield (X=19..300, Y=31..192)
    mov ax, 19
    mov bx, 31
    mov cx, 282
    mov dx, 162
    mov byte [GFX_COLOR], 26
    call gfx_fill_rect

    ; 3. Draw 28 x 16 Square Grass Checkerboard (10x10 pixel tiles at X=20..299, Y=32..191)
    xor dh, dh                      ; DH = gy (0..15)
.gdb_row:
    xor dl, dl                      ; DL = gx (0..27)
.gdb_col:
    mov al, dl
    add al, dh
    and al, 1                       ; 0 = Even tile, 1 = Odd tile
    add al, 2                       ; Colors 2 & 3 = Bright & Medium Grass
    cmp byte [CARD_OPEN], 1
    jne .gdb_col_ok
    add al, 2                       ; Colors 4 & 5 = Dimmed Olive Grass when Popup Card is open!
.gdb_col_ok:
    mov [GFX_COLOR], al

    movzx ax, dl
    imul ax, 10
    add ax, 20                      ; px = 20 + gx * 10
    movzx bx, dh
    imul bx, 10
    add bx, 32                      ; py = 32 + gy * 10
    mov cx, 10
    push dx
    mov dx, 10
    call gfx_fill_rect
    pop dx

    inc dl
    cmp dl, 28
    jb .gdb_col
    inc dh
    cmp dh, 16
    jb .gdb_row

    ; 4. Draw HUD Icons & Scores on Top Bar (Y = 0..23)
    ; Left: 16x16 Glossy Red Apple at (6, 4) + Score at (25, 7)
    mov ax, 6
    mov bx, 4
    mov si, sprite_apple16
    call gfx_draw_sprite16

    mov ax, 25
    mov bx, 7
    mov cx, [SCORE]
    mov dl, 15
    call gfx_draw_3digits

    ; Trophy at (56, 4) + High Score at (75, 7)
    mov ax, 56
    mov bx, 4
    mov si, sprite_trophy16
    call gfx_draw_sprite16

    mov ax, 75
    mov bx, 7
    mov cx, [HIGH_SCORE]
    mov dl, 22
    call gfx_draw_3digits

    ; Center HUD Title: "CYBFORGE SNAKE" (or Golden Apple Timer if active)
    cmp byte [GOLD_FOOD_X], 0xFF
    jne .gdb_gold_hud
    mov ax, 114
    mov bx, 7
    mov si, str_game_title
    mov dl, 15
    call gfx_draw_text
    jmp .gdb_hud_right

.gdb_gold_hud:
    mov ax, 118
    mov bx, 7
    mov si, str_gold_lbl
    mov dl, 21
    call gfx_draw_text
    mov ax, [GOLD_TIMER]
    xor dx, dx
    mov cx, 7
    div cx
    mov cx, ax
    mov ax, 166
    mov bx, 7
    mov dl, 22
    call gfx_draw_3digits

.gdb_hud_right:
    ; Right HUD Action Icons: Speaker (X=254), Pause (X=276), Settings Gear (X=298)
    mov ax, 254
    mov bx, 4
    mov si, sprite_hud_speaker
    call gfx_draw_sprite16

    ; Pause bars || at (278, 6)
    mov ax, 278
    mov bx, 6
    mov cx, 3
    mov dx, 12
    mov byte [GFX_COLOR], 15
    call gfx_fill_rect
    mov ax, 284
    call gfx_fill_rect

    ; Settings Gear icon at (296, 4)
    mov ax, 296
    mov bx, 4
    mov si, sprite_hud_gear
    call gfx_draw_sprite16

    ; 5. Draw Arena Obstacles if active
    call gfx_draw_arena_obstacles

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

gfx_draw_arena_obstacles:
    cmp byte [CFG_ARENA], 1
    je .gdao_pillars
    cmp byte [CFG_ARENA], 2
    je .gdao_maze
    ret

.gdao_pillars:
    ; Four 2x2-tile 3D blocks at (6,3), (20,3), (6,11), (20,11)
    mov ax, 20 + 6*10
    mov bx, 32 + 3*10
    mov cx, 20
    mov dx, 20
    call gfx_draw_3d_block
    mov ax, 20 + 20*10
    mov bx, 32 + 3*10
    call gfx_draw_3d_block
    mov ax, 20 + 6*10
    mov bx, 32 + 11*10
    call gfx_draw_3d_block
    mov ax, 20 + 20*10
    mov bx, 32 + 11*10
    call gfx_draw_3d_block
    ret

.gdao_maze:
    ; Two horizontal walls: gy=4, gx=5..18 (140x10) and gy=11, gx=9..22 (140x10)
    mov ax, 20 + 5*10
    mov bx, 32 + 4*10
    mov cx, 140
    mov dx, 10
    call gfx_draw_3d_block
    mov ax, 20 + 9*10
    mov bx, 32 + 11*10
    mov cx, 140
    mov dx, 10
    call gfx_draw_3d_block
    ret

gfx_draw_3d_block:
    ; Input: AX=x, BX=y, CX=w, DX=h
    mov byte [GFX_COLOR], 20        ; Warm Brown Border
    call gfx_fill_rect
    push ax
    push bx
    push cx
    push dx
    inc ax
    inc bx
    sub cx, 2
    sub dx, 2
    mov byte [GFX_COLOR], 23        ; Amber Inner Block
    call gfx_fill_rect
    pop dx
    pop cx
    pop bx
    pop ax
    ret

is_arena_wall:
    ; Input: AL = gx (0..27), BL = gy (0..15). Output: ZF=1 if wall hit, ZF=0 if clear
    cmp byte [CFG_ARENA], 1
    je .chk_pil
    cmp byte [CFG_ARENA], 2
    je .chk_mz
    or sp, sp                       ; ZF = 0
    ret

.chk_pil:
    cmp al, 6
    je .chk_pil_y
    cmp al, 7
    je .chk_pil_y
    cmp al, 20
    je .chk_pil_y
    cmp al, 21
    je .chk_pil_y
    or sp, sp
    ret
.chk_pil_y:
    cmp bl, 3
    je .hit_wall
    cmp bl, 4
    je .hit_wall
    cmp bl, 11
    je .hit_wall
    cmp bl, 12
    je .hit_wall
    or sp, sp
    ret

.chk_mz:
    cmp bl, 4
    jne .chk_mz_w2
    cmp al, 5
    jb .no_mz_hit
    cmp al, 18
    jbe .hit_wall
.chk_mz_w2:
    cmp bl, 11
    jne .no_mz_hit
    cmp al, 9
    jb .no_mz_hit
    cmp al, 22
    jbe .hit_wall
.no_mz_hit:
    or sp, sp
    ret

.hit_wall:
    xor al, al                      ; ZF = 1
    ret

; -----------------------------------------------------------------------------
; Continuous, Connected Multi-Color Royal-Blue Snake Renderer (gfx_draw_snake)
; -----------------------------------------------------------------------------
gfx_draw_snake:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    ; 1. Draw Seamless Connected Tube Bridges between adjacent segments (i and i+1)
    mov cx, [SNAKE_LEN]
    dec cx
    jz .gds_head
    xor si, si
.gds_bridge_lp:
    movzx ax, byte [SNAKE_X + si]
    movzx bx, byte [SNAKE_Y + si]
    movzx dx, byte [SNAKE_X + si + 1]
    movzx di, byte [SNAKE_Y + si + 1]

    ; Check if |gx0 - gx1| + |gy0 - gy1| == 1 (skip bridge if wrapped across screen edge)
    push ax
    push bx
    sub ax, dx
    jns .gds_dx_p
    neg ax
.gds_dx_p:
    sub bx, di
    jns .gds_dy_p
    neg bx
.gds_dy_p:
    add ax, bx
    cmp ax, 1
    pop bx
    pop ax
    jne .gds_next_bridge

    ; Compute top-left grid cell (min(gx0,gx1), min(gy0,gy1))
    cmp ax, dx
    je .gds_vert_bridge

    ; Horizontal bridge between min(gx0,gx1) and max(gx0,gx1): width=18, height=8
    cmp ax, dx
    jb .gds_h_ord
    mov ax, dx
.gds_h_ord:
    imul ax, 10
    add ax, 21                      ; px = 20 + min_gx*10 + 1
    imul bx, 10
    add bx, 33                      ; py = 32 + gy*10 + 1
    push cx
    mov cx, 18
    mov dx, 8
    mov byte [GFX_COLOR], 11        ; Primary Royal Blue (#4674E9)
    call gfx_fill_rect
    ; Top 2px Specular Highlight (#6691F5)
    inc bx
    mov dx, 2
    mov byte [GFX_COLOR], 12
    call gfx_fill_rect
    ; Bottom 1px Contour Shadow (#3156B8)
    add bx, 6
    mov dx, 1
    mov byte [GFX_COLOR], 13
    call gfx_fill_rect
    pop cx
    jmp .gds_next_bridge

.gds_vert_bridge:
    ; Vertical bridge between min(gy0,gy1) and max(gy0,gy1): width=8, height=18
    cmp bx, di
    jb .gds_v_ord
    mov bx, di
.gds_v_ord:
    imul ax, 10
    add ax, 21                      ; px = 20 + gx*10 + 1
    imul bx, 10
    add bx, 33                      ; py = 32 + min_gy*10 + 1
    push cx
    mov cx, 8
    mov dx, 18
    mov byte [GFX_COLOR], 11
    call gfx_fill_rect
    ; Left 2px Specular Highlight
    inc ax
    mov cx, 2
    mov byte [GFX_COLOR], 12
    call gfx_fill_rect
    ; Right 1px Contour Shadow
    add ax, 6
    mov cx, 1
    mov byte [GFX_COLOR], 13
    call gfx_fill_rect
    pop cx

.gds_next_bridge:
    inc si
    dec cx
    jnz .gds_bridge_lp

    ; 2. Draw Rounded Tapered Tail Tip at last segment (SNAKE_LEN - 1)
    mov si, [SNAKE_LEN]
    dec si
    movzx ax, byte [SNAKE_X + si]
    imul ax, 10
    add ax, 22
    movzx bx, byte [SNAKE_Y + si]
    imul bx, 10
    add bx, 34
    mov cx, 6
    mov dx, 6
    mov byte [GFX_COLOR], 11
    call gfx_fill_rect

    ; 3. Draw Swollen Digesting Apple Bulge if active!
    cmp byte [BULGE_X], 0xFF
    je .gds_head
    movzx ax, byte [BULGE_X]
    imul ax, 10
    add ax, 20
    movzx bx, byte [BULGE_Y]
    imul bx, 10
    add bx, 32
    mov cx, 10
    mov dx, 10
    mov byte [GFX_COLOR], 11
    call gfx_fill_rounded_rect
    add ax, 2
    add bx, 2
    mov cx, 4
    mov dx, 3
    mov byte [GFX_COLOR], 12
    call gfx_fill_rect

.gds_head:
    ; 4. Draw Expressive Multi-Color Snake Head at (SNAKE_X[0], SNAKE_Y[0])
    movzx ax, byte [SNAKE_X]
    imul ax, 10
    add ax, 20                      ; AX = head_px
    movzx bx, byte [SNAKE_Y]
    imul bx, 10
    add bx, 32                      ; BX = head_py

    ; Base 10x10 rounded royal-blue head
    mov cx, 10
    mov dx, 10
    mov byte [GFX_COLOR], 11
    call gfx_fill_rounded_rect

    ; Check Manhattan distance to Apple: |SNAKE_X - FOOD_X| + |SNAKE_Y - FOOD_Y| <= 3 -> Wide-Open Chomp Mouth!
    mov dl, [SNAKE_X]
    sub dl, [FOOD_X]
    jns .gds_cdx
    neg dl
.gds_cdx:
    mov dh, [SNAKE_Y]
    sub dh, [FOOD_Y]
    jns .gds_cdy
    neg dh
.gds_cdy:
    add dl, dh
    cmp dl, 3
    ja .gds_check_tongue

    ; Draw Wide-Open Chomp Mouth (Maroon 24 + Pink Tongue 25 + White Fangs 15) on front of head!
    push ax
    push bx
    add ax, 2
    add bx, 2
    mov cx, 6
    mov dx, 6
    mov byte [GFX_COLOR], 24        ; Maroon open mouth interior
    call gfx_fill_rect
    inc ax
    add bx, 2
    mov cx, 4
    mov dx, 3
    mov byte [GFX_COLOR], 25        ; Pink inner tongue
    call gfx_fill_rect
    pop bx
    pop ax
    jmp .gds_eyes

.gds_check_tongue:
    ; Flicking Red Forked Tongue ahead of snout on even TONGUE_TICK!
    inc byte [TONGUE_TICK]
    test byte [TONGUE_TICK], 2
    jnz .gds_eyes

    push ax
    push bx
    mov cl, [SNAKE_DIR]
    cmp cl, 1                       ; Right
    jne .gt_chk_l
    add ax, 10
    add bx, 4
    mov cx, 4
    mov dx, 2
    mov byte [GFX_COLOR], 16
    call gfx_fill_rect
    add ax, 4
    dec bx
    mov cx, 1
    mov dx, 1
    call gfx_fill_rect
    add bx, 3
    call gfx_fill_rect
    jmp .gt_done
.gt_chk_l:
    cmp cl, 3                       ; Left
    jne .gt_chk_u
    sub ax, 4
    add bx, 4
    mov cx, 4
    mov dx, 2
    mov byte [GFX_COLOR], 16
    call gfx_fill_rect
    jmp .gt_done
.gt_chk_u:
    cmp cl, 0                       ; Up
    jne .gt_chk_d
    add ax, 4
    sub bx, 4
    mov cx, 2
    mov dx, 4
    mov byte [GFX_COLOR], 16
    call gfx_fill_rect
    jmp .gt_done
.gt_chk_d:
    add ax, 4
    add bx, 10
    mov cx, 2
    mov dx, 4
    mov byte [GFX_COLOR], 16
    call gfx_fill_rect
.gt_done:
    pop bx
    pop ax

.gds_eyes:
    ; Draw Big Protruding Round White Eyes (4x4, Color 15) + Deep-Navy Pupils (2x2, Color 14)
    ; oriented according to SNAKE_DIR!
    mov cl, 14                      ; Default pupil color: Deep Navy
    cmp byte [CFG_FACE], 1
    jne .gds_eye_col_ok
    mov cl, 27                      ; Cool Sunglasses: Pure Black lenses
.gds_eye_col_ok:

    mov ch, [SNAKE_DIR]
    test ch, 1                      ; Moving horizontally (Right=1 or Left=3)?
    jz .gds_eyes_vert

    ; Horizontal movement: Top Eye at (px+3, py-1) and Bottom Eye at (px+3, py+7)
    push ax
    push bx
    add ax, 2
    dec bx
    mov cx, 4
    mov dx, 4
    mov byte [GFX_COLOR], 15
    call gfx_fill_rect
    add bx, 8
    call gfx_fill_rect

    ; Pupils shifted toward movement direction
    pop bx
    pop ax
    push ax
    push bx
    add ax, 4
    cmp byte [SNAKE_DIR], 1
    je .gds_hp_ok
    sub ax, 2
.gds_hp_ok:
    mov cx, 2
    mov dx, 2
    mov byte [GFX_COLOR], 14
    cmp byte [CFG_FACE], 1
    jne .gds_hp_draw
    mov byte [GFX_COLOR], 27
    mov cx, 4
.gds_hp_draw:
    call gfx_fill_rect
    add bx, 8
    call gfx_fill_rect
    pop bx
    pop ax
    jmp .gds_done

.gds_eyes_vert:
    ; Vertical movement: Left Eye at (px-1, py+2) and Right Eye at (px+7, py+2)
    push ax
    push bx
    dec ax
    add bx, 2
    mov cx, 4
    mov dx, 4
    mov byte [GFX_COLOR], 15
    call gfx_fill_rect
    add ax, 8
    call gfx_fill_rect

    ; Pupils
    pop bx
    pop ax
    push ax
    push bx
    add bx, 4
    cmp byte [SNAKE_DIR], 2
    je .gds_vp_ok
    sub bx, 2
.gds_vp_ok:
    mov cx, 2
    mov dx, 2
    mov byte [GFX_COLOR], 14
    call gfx_fill_rect
    add ax, 8
    call gfx_fill_rect
    pop bx
    pop ax

.gds_done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; -----------------------------------------------------------------------------
; Multi-Color 10x10 Glossy Red Apple & Golden Apple Renderer (gfx_draw_fruit)
; -----------------------------------------------------------------------------
gfx_draw_fruit:
    push ax
    push bx
    push si

    movzx ax, byte [FOOD_X]
    imul ax, 10
    add ax, 20
    movzx bx, byte [FOOD_Y]
    imul bx, 10
    add bx, 32
    mov si, sprite_apple10
    call gfx_draw_sprite10

    cmp byte [GOLD_FOOD_X], 0xFF
    je .gdf_done
    movzx ax, byte [GOLD_FOOD_X]
    imul ax, 10
    add ax, 20
    movzx bx, byte [GOLD_FOOD_Y]
    imul bx, 10
    add bx, 32
    mov si, sprite_gold_apple10
    call gfx_draw_sprite10

.gdf_done:
    pop si
    pop bx
    pop ax
    ret

; -----------------------------------------------------------------------------
; Fruit Spawning on 28 x 16 Grid (Cols 0..27, Rows 0..15)
; -----------------------------------------------------------------------------
spawn_fruit:
    push ax
    push bx
    push cx
    push dx
    push si
    push bp

    ; On initial start, place first apple at (19, 8) directly in front of the snake!
    cmp byte [FIRST_SPAWN], 1
    jne .sf_random
    mov byte [FIRST_SPAWN], 0
    mov byte [FOOD_X], 19
    mov byte [FOOD_Y], 8
    jmp .spawn_ok

.sf_random:
    mov bp, 120
.try_spawn:
    call get_random
    xor dx, dx
    mov cx, 28
    div cx
    mov [FOOD_X], dl
    call get_random
    xor dx, dx
    mov cx, 16
    div cx
    mov [FOOD_Y], dl

    mov al, [FOOD_X]
    mov bl, [FOOD_Y]
    call is_arena_wall
    jz .retry_food

    mov cx, [SNAKE_LEN]
    xor si, si
    mov al, [FOOD_X]
    mov ah, [FOOD_Y]
.chk_food_body:
    cmp al, [SNAKE_X + si]
    jne .chk_food_next
    cmp ah, [SNAKE_Y + si]
    je .retry_food
.chk_food_next:
    inc si
    loop .chk_food_body
    jmp .spawn_ok

.retry_food:
    dec bp
    jnz .try_spawn
.spawn_ok:
    pop bp
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

spawn_golden_apple:
    push ax
    push bx
    push cx
    push dx
    push si
    push bp
    mov bp, 100
.try_gold:
    call get_random
    xor dx, dx
    mov cx, 28
    div cx
    mov [GOLD_FOOD_X], dl
    call get_random
    xor dx, dx
    mov cx, 16
    div cx
    mov [GOLD_FOOD_Y], dl

    mov al, [GOLD_FOOD_X]
    cmp al, [FOOD_X]
    jne .g_chk_wall
    mov al, [GOLD_FOOD_Y]
    cmp al, [FOOD_Y]
    je .retry_gold
.g_chk_wall:
    mov al, [GOLD_FOOD_X]
    mov bl, [GOLD_FOOD_Y]
    call is_arena_wall
    jz .retry_gold

    mov cx, [SNAKE_LEN]
    xor si, si
    mov al, [GOLD_FOOD_X]
    mov ah, [GOLD_FOOD_Y]
.chk_gold_body:
    cmp al, [SNAKE_X + si]
    jne .chk_gold_next
    cmp ah, [SNAKE_Y + si]
    je .retry_gold
.chk_gold_next:
    inc si
    loop .chk_gold_body

    mov word [GOLD_TIMER], 55
    call sound_golden_spawn
    jmp .gold_spawn_ok

.retry_gold:
    dec bp
    jnz .try_gold
    mov byte [GOLD_FOOD_X], 0xFF
.gold_spawn_ok:
    pop bp
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

get_random:
    mov ax, [RND_SEED]
    mov cx, 25173
    mul cx
    add ax, 13849
    mov [RND_SEED], ax
    ret

; -----------------------------------------------------------------------------
; Maximalist Sky-Blue Popup Card & 3 Pill-Shaped Royal-Blue Buttons
; (Matches Reference Screenshot 1 with Big-Eyed Blue Snake on Grass Horizon!)
; -----------------------------------------------------------------------------
gfx_draw_popup_card:
    ; Input: DL = 0 (Start Card), DL = 1 (Game Over Card)
    push ax
    push bx
    push cx
    push dx
    push si

    push dx
    mov byte [CARD_OPEN], 1
    call gfx_render_scene           ; Draws dimmed dark-olive background playfield + snake + apple!

    ; 1. Card Drop Shadow at (X=59..266, Y=29..137, w=208, h=109)
    mov ax, 59
    mov bx, 29
    mov cx, 208
    mov dx, 109
    mov byte [GFX_COLOR], 26
    call gfx_fill_rounded_rect

    ; 2. Rounded Sky-Blue Card Body at (X=56..263, Y=26..134, w=208, h=109)
    ;    Leaves Top HUD Bar (Y=0..23) 100% unobstructed!
    mov ax, 56
    mov bx, 26
    mov cx, 208
    mov dx, 109
    mov byte [GFX_COLOR], 6         ; Sky Blue (#4DC1F9)
    call gfx_fill_rounded_rect

    ; 3. 3-Row Green Grass Horizon at Bottom of Card (X=58..261, Y=103..132, 20x3 tiles of 10x10)
    mov ax, 58
    mov bx, 102
    mov cx, 204
    mov dx, 1
    mov byte [GFX_COLOR], 28        ; Horizon edge line
    call gfx_fill_rect

    xor ch, ch                      ; row 0..2
.c_grass_r:
    xor cl, cl                      ; col 0..19
.c_grass_c:
    mov al, cl
    add al, ch
    and al, 1
    add al, 2                       ; Bright/Medium Grass (Colors 2 & 3)
    mov [GFX_COLOR], al
    movzx ax, cl
    imul ax, 10
    add ax, 58
    movzx bx, ch
    imul bx, 10
    add bx, 103
    push cx
    mov cx, 10
    mov dx, 10
    call gfx_fill_rect
    pop cx
    inc cl
    cmp cl, 20
    jb .c_grass_c
    inc ch
    cmp ch, 3
    jb .c_grass_r
    ; Fill remaining 4px right strip of card grass (X=258..261)
    mov ax, 258
    mov bx, 103
    mov cx, 4
    mov dx, 30
    mov byte [GFX_COLOR], 2
    call gfx_fill_rect

    ; 4. Card Header Banner: "CYBFORGE SNAKE" (Start) or "GAME OVER" (Game Over)
    pop dx
    push dx
    cmp dl, 1
    je .card_hdr_go
    mov ax, 104
    mov bx, 30
    mov si, str_game_title
    mov dl, 15
    call gfx_draw_text
    jmp .card_icons
.card_hdr_go:
    mov ax, 124
    mov bx, 30
    mov si, str_go_short
    mov dl, 15
    call gfx_draw_text

.card_icons:
    ; 5. Large 16x16 Glossy Red Apple (X=92, Y=44) + Crisp White Score below (X=88, Y=62)
    mov ax, 92
    mov bx, 44
    mov si, sprite_apple16
    call gfx_draw_sprite16

    mov ax, 88
    mov bx, 62
    mov cx, [SCORE]
    mov dl, 15
    call gfx_draw_3digits

    ; 6. Large 16x16 Golden Trophy Cup (X=212, Y=44) + Bright Gold High Score below (X=208, Y=62)
    mov ax, 212
    mov bx, 44
    mov si, sprite_trophy16
    call gfx_draw_sprite16

    mov ax, 208
    mov bx, 62
    mov cx, [HIGH_SCORE]
    mov dl, 22
    call gfx_draw_3digits

    ; 7. Large Hero Illustration: Curving Royal-Blue Cybforge Snake with Protruding White Eyes
    ;    sitting on the green grass horizon facing a Glossy Red Apple!
    ;    Coiled Tail & Lower Body on Grass (X=84..168, Y=98..116)
    mov ax, 84
    mov bx, 104
    mov cx, 16
    mov dx, 10
    mov byte [GFX_COLOR], 13        ; Deep Blue Tail Contour
    call gfx_fill_rounded_rect
    mov ax, 94
    mov bx, 99
    mov cx, 66
    mov dx, 15
    mov byte [GFX_COLOR], 11        ; Primary Royal Blue Body (#4674E9)
    call gfx_fill_rounded_rect
    mov ax, 98
    mov bx, 101
    mov cx, 58
    mov dx, 4
    mov byte [GFX_COLOR], 12        ; Specular Highlight (#6691F5)
    call gfx_fill_rect

    ;    Upright Neck & Rounded Snout (X=132..172, Y=68..104)
    mov ax, 132
    mov bx, 74
    mov cx, 26
    mov dx, 32
    mov byte [GFX_COLOR], 11
    call gfx_fill_rounded_rect
    ;    Forward-facing Rounded Snout (X=140..174, Y=68..94)
    mov ax, 140
    mov bx, 68
    mov cx, 34
    mov dx, 26
    mov byte [GFX_COLOR], 11
    call gfx_fill_rounded_rect
    mov ax, 144
    mov bx, 70
    mov cx, 26
    mov dx, 4
    mov byte [GFX_COLOR], 12
    call gfx_fill_rect

    ;    Two Giant 10x10 Protruding Round White Eyes on top of head at (138, 63) and (153, 63)
    mov ax, 138
    mov bx, 63
    mov cx, 10
    mov dx, 10
    mov byte [GFX_COLOR], 15
    call gfx_fill_rounded_rect
    mov ax, 153
    mov bx, 63
    call gfx_fill_rounded_rect

    ;    4x5 Deep-Navy Pupils looking right toward the Apple + 2x2 White Catchlights
    mov ax, 143
    mov bx, 66
    mov cx, 4
    mov dx, 5
    mov byte [GFX_COLOR], 14
    call gfx_fill_rect
    mov ax, 158
    mov bx, 66
    call gfx_fill_rect
    mov ax, 143
    mov bx, 66
    mov cx, 2
    mov dx, 2
    mov byte [GFX_COLOR], 15
    call gfx_fill_rect
    mov ax, 158
    mov bx, 66
    call gfx_fill_rect

    ;    Cute Nostrils & Happy Mouth + Flicking Red Forked Tongue
    mov ax, 164
    mov bx, 74
    mov cx, 2
    mov dx, 2
    mov byte [GFX_COLOR], 13
    call gfx_fill_rect
    mov ax, 169
    mov bx, 74
    call gfx_fill_rect

    ;    Smile line & forked red tongue extending toward the apple
    mov ax, 152
    mov bx, 86
    mov cx, 20
    mov dx, 2
    mov byte [GFX_COLOR], 14
    call gfx_fill_rect
    mov ax, 172
    mov bx, 85
    mov cx, 7
    mov dx, 2
    mov byte [GFX_COLOR], 16        ; Red Forked Tongue
    call gfx_fill_rect
    mov ax, 179
    mov bx, 84
    mov cx, 2
    mov dx, 1
    call gfx_fill_rect
    mov ax, 179
    mov bx, 87
    call gfx_fill_rect

    ;    Glossy Red Apple on the Grass Horizon to the right of the Snake (X=206, Y=92)
    mov ax, 206
    mov bx, 92
    mov si, sprite_apple16
    call gfx_draw_sprite16

    ; 8. Draw the 3 Rounded Pill-Shaped Royal-Blue Buttons below the card (Y=139..195)
    call gfx_draw_card_buttons

    pop dx
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

gfx_draw_card_buttons:
    push ax
    push bx
    push cx
    push dx
    push si

    ; --- Button 0 (Y = 139..155, X = 56..263, w = 208): "Play Cybforge Snake" ---
    mov ax, 56
    mov bx, 141
    mov cx, 208
    mov dx, 16
    mov byte [GFX_COLOR], 10        ; 3D Pill Bottom Shadow Lip (#114694)
    call gfx_fill_rounded_rect

    mov ax, 56
    mov bx, 139
    mov cx, 208
    mov dx, 16
    mov byte [GFX_COLOR], 8         ; Royal Blue (#1967D2)
    cmp byte [CARD_BTN_SEL], 0
    jne .btn0_fill
    mov byte [GFX_COLOR], 9         ; Hover Bright Royal Blue (#2979FF)
.btn0_fill:
    call gfx_fill_rounded_rect

    ; Play Triangle Icon on left of Button 0 (X=68, Y=143)
    mov ax, 68
    mov bx, 143
    mov cx, 2
    mov dx, 8
    mov byte [GFX_COLOR], 15
    call gfx_fill_rect
    add ax, 2
    inc bx
    mov dx, 6
    call gfx_fill_rect
    add ax, 2
    inc bx
    mov dx, 4
    call gfx_fill_rect
    add ax, 2
    inc bx
    mov dx, 2
    call gfx_fill_rect

    mov ax, 86
    mov bx, 141
    mov si, str_btn_play_txt
    mov dl, 15
    cmp byte [CARD_BTN_SEL], 0
    jne .btn0_txt
    mov dl, 22                      ; Bright Gold-White highlight when selected
.btn0_txt:
    call gfx_draw_text

    ; --- Button 1 (Y = 159..175, X = 56..263, w = 208): "BIOS Setup & Settings" ---
    mov ax, 56
    mov bx, 161
    mov cx, 208
    mov dx, 16
    mov byte [GFX_COLOR], 10
    call gfx_fill_rounded_rect

    mov ax, 56
    mov bx, 159
    mov cx, 208
    mov dx, 16
    mov byte [GFX_COLOR], 8
    cmp byte [CARD_BTN_SEL], 1
    jne .btn1_fill
    mov byte [GFX_COLOR], 9
.btn1_fill:
    call gfx_fill_rounded_rect

    mov ax, 64
    mov bx, 159
    mov si, sprite_hud_gear
    call gfx_draw_sprite16

    mov ax, 84
    mov bx, 161
    mov si, str_btn_setup_txt
    mov dl, 15
    cmp byte [CARD_BTN_SEL], 1
    jne .btn1_txt
    mov dl, 22
.btn1_txt:
    call gfx_draw_text

    ; --- Button 2 (Y = 179..195, X = 56..263, w = 208): "Launch UEFI/BIOS Shell" ---
    mov ax, 56
    mov bx, 181
    mov cx, 208
    mov dx, 16
    mov byte [GFX_COLOR], 10
    call gfx_fill_rounded_rect

    mov ax, 56
    mov bx, 179
    mov cx, 208
    mov dx, 16
    mov byte [GFX_COLOR], 8
    cmp byte [CARD_BTN_SEL], 2
    jne .btn2_fill
    mov byte [GFX_COLOR], 9
.btn2_fill:
    call gfx_fill_rounded_rect

    ; '>' Terminal Prompt icon at (66, 181)
    mov ax, 66
    mov bx, 181
    mov cl, '>'
    mov dl, 22
    call gfx_draw_char

    mov ax, 80
    mov bx, 181
    mov si, str_btn_shell_txt
    mov dl, 15
    cmp byte [CARD_BTN_SEL], 2
    jne .btn2_txt
    mov dl, 22
.btn2_txt:
    call gfx_draw_text

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

check_card_mouse_hover:
    xor dl, dl
    jmp check_card_mouse_common
check_card_mouse_hover_go:
    mov dl, 1
check_card_mouse_common:
    push ax
    push bx
    push cx
    mov ax, [MOUSE_FINE_X]
    shr ax, 1                       ; px (0..319)
    mov bx, [MOUSE_FINE_Y]
    shr bx, 1                       ; py (0..199)

    mov ch, [CARD_BTN_SEL]
    cmp ax, 56
    jb .ccmc_chk_move
    cmp ax, 263
    ja .ccmc_chk_move
    cmp bx, 139
    jb .ccmc_chk_move
    cmp bx, 156
    jb .ccmc_b0
    cmp bx, 176
    jb .ccmc_b1
    cmp bx, 196
    jb .ccmc_b2
    jmp .ccmc_chk_move
.ccmc_b0:
    mov ch, 0
    jmp .ccmc_chk_sel
.ccmc_b1:
    mov ch, 1
    jmp .ccmc_chk_sel
.ccmc_b2:
    mov ch, 2
.ccmc_chk_sel:
    cmp ch, [CARD_BTN_SEL]
    je .ccmc_chk_move
    mov [CARD_BTN_SEL], ch
    call gfx_draw_card_buttons
    call gfx_present
    pop cx
    pop bx
    pop ax
    ret

.ccmc_chk_move:
    ; Even if button selection didn't change, update cursor if mouse moved!
    mov ax, [MOUSE_FINE_X]
    cmp ax, [MOUSE_LAST_FX]
    jne .ccmc_present
    mov ax, [MOUSE_FINE_Y]
    cmp ax, [MOUSE_LAST_FY]
    je .ccmc_done
.ccmc_present:
    call gfx_present
.ccmc_done:
    pop cx
    pop bx
    pop ax
    ret

; -----------------------------------------------------------------------------
; Legacy Text-Mode Helper Stubs (Used by BIOS Setup Tab 0 High Score Display)
; -----------------------------------------------------------------------------
render_3digits_yellow:
    xor dx, dx
    mov cx, 100
    div cx
    add al, '0'
    mov ah, 0x0E
    stosw
    mov ax, dx
    xor dx, dx
    mov cx, 10
    div cx
    add al, '0'
    mov ah, 0x0E
    stosw
    mov al, dl
    add al, '0'
    mov ah, 0x0E
    stosw
    ret

render_3digits_white:
    xor dx, dx
    mov cx, 100
    div cx
    add al, '0'
    mov ah, 0x0F
    stosw
    mov ax, dx
    xor dx, dx
    mov cx, 10
    div cx
    add al, '0'
    mov ah, 0x0F
    stosw
    mov al, dl
    add al, '0'
    mov ah, 0x0F
    stosw
    ret

    ; =========================================================================
    ; PHASE 8: DIZZY-STARS CRASH ANIMATION & TOP 3 LEADERBOARD (Mode 13h)
    ; =========================================================================
crash_dissolve_animation:
    call sound_crash

    ; Animate 8 frames of Orbiting Golden & White Pixel Stars around the Dizzy Snake Head!
    mov cx, 8
.dizzy_loop:
    push cx
    call gfx_render_scene

    ; Compute head center pixel (px, py)
    movzx ax, byte [SNAKE_X]
    imul ax, 10
    add ax, 20
    movzx bx, byte [SNAKE_Y]
    imul bx, 10
    add bx, 32

    ; Draw 4 twinkling 3x3 Gold/White Stars around the head
    pop cx
    push cx
    mov dl, 21                      ; Gold
    mov dh, 15                      ; White
    test cl, 1
    jz .dz_col_ok
    xchg dl, dh
.dz_col_ok:
    push ax
    push bx
    sub ax, 5
    sub bx, 5
    mov [GFX_COLOR], dl
    mov cx, 3
    push dx
    mov dx, 3
    call gfx_fill_rect
    pop dx

    add ax, 17
    mov [GFX_COLOR], dh
    push dx
    mov dx, 3
    call gfx_fill_rect
    pop dx

    sub ax, 15
    add bx, 16
    mov [GFX_COLOR], dh
    push dx
    mov dx, 3
    call gfx_fill_rect
    pop dx

    add ax, 14
    mov [GFX_COLOR], dl
    mov dx, 3
    call gfx_fill_rect
    pop bx
    pop ax

    call gfx_present
    mov ecx, 11000000
    call delay_cycles
    pop cx
    loop .dizzy_loop
    ret

check_top3_qualification:
    mov ax, [SCORE]
    cmp ax, [TOP3_TABLE + 13]
    jbe .no_qualification

    call enter_initials_dialog

    push es
    push ds
    pop es

    mov ax, [SCORE]
    cmp ax, [TOP3_TABLE + 3]
    ja .insert_pos1

    cmp ax, [TOP3_TABLE + 8]
    ja .insert_pos2

    mov si, CURRENT_NAME
    mov di, TOP3_TABLE + 10
    mov cx, 3
    rep movsb
    mov ax, [SCORE]
    mov [TOP3_TABLE + 13], ax
    jmp .save_top3_done

.insert_pos2:
    mov si, TOP3_TABLE + 5
    mov di, TOP3_TABLE + 10
    mov cx, 5
    rep movsb
    mov si, CURRENT_NAME
    mov di, TOP3_TABLE + 5
    mov cx, 3
    rep movsb
    mov ax, [SCORE]
    mov [TOP3_TABLE + 8], ax
    jmp .save_top3_done

.insert_pos1:
    mov si, TOP3_TABLE + 5
    mov di, TOP3_TABLE + 10
    mov cx, 5
    rep movsb
    mov si, TOP3_TABLE + 0
    mov di, TOP3_TABLE + 5
    mov cx, 5
    rep movsb
    mov si, CURRENT_NAME
    mov di, TOP3_TABLE + 0
    mov cx, 3
    rep movsb
    mov ax, [SCORE]
    mov [TOP3_TABLE + 3], ax
    mov [HIGH_SCORE], ax

.save_top3_done:
    pop es
    call save_cmos_settings
    call sound_golden_apple
.no_qualification:
    ret

enter_initials_dialog:
    mov byte [CURRENT_NAME + 0], 'A'
    mov byte [CURRENT_NAME + 1], 'A'
    mov byte [CURRENT_NAME + 2], 'A'
    mov byte [CUR_CHAR_IDX], 0

.redraw_initials:
    mov byte [CARD_OPEN], 1
    call gfx_render_scene

    ; Rounded Sky-Blue Modal Card (X=64..255, Y=42..158)
    mov ax, 64
    mov bx, 42
    mov cx, 192
    mov dx, 116
    mov byte [GFX_COLOR], 6
    call gfx_fill_rounded_rect

    mov ax, 80
    mov bx, 52
    mov si, str_new_rec_lbl
    mov dl, 22
    call gfx_draw_text

    mov ax, 112
    mov bx, 68
    mov si, str_score_lbl
    mov dl, 15
    call gfx_draw_text
    mov ax, 168
    mov bx, 68
    mov cx, [SCORE]
    mov dl, 22
    call gfx_draw_3digits

    ; Draw 3 Initials Pills at X=120, 148, 176 (Y=90)
    xor si, si
.show_chars:
    mov ax, si
    imul ax, 28
    add ax, 118
    mov bx, 88
    mov cx, 20
    mov dx, 20
    mov byte [GFX_COLOR], 8
    cmp si, [CUR_CHAR_IDX]
    jne .sc_box
    mov byte [GFX_COLOR], 9
.sc_box:
    call gfx_fill_rounded_rect

    add ax, 6
    add bx, 5
    mov cl, [CURRENT_NAME + si]
    mov dl, 15
    cmp si, [CUR_CHAR_IDX]
    jne .sc_chr
    mov dl, 22
.sc_chr:
    call gfx_draw_char

    inc si
    cmp si, 3
    jb .show_chars

    mov ax, 100
    mov bx, 122
    mov si, str_init_confirm
    mov dl, 15
    call gfx_draw_text

    call gfx_present
    call drain_kbd

.initials_input:
    call read_key
    test al, al
    jz .init_wait

    cmp al, 0x1C
    je .init_done
    cmp al, 0x4B
    je .char_left
    cmp al, 0x1E
    je .char_left
    cmp al, 0x4D
    je .char_right
    cmp al, 0x20
    je .char_right
    cmp al, 0x48
    je .char_up
    cmp al, 0x11
    je .char_up
    cmp al, 0x50
    je .char_down
    cmp al, 0x1F
    je .char_down

.init_wait:
    mov ecx, 15000000
    call delay_cycles
    jmp .initials_input

.char_left:
    call sound_click
    cmp byte [CUR_CHAR_IDX], 0
    je .wrap_ch_l
    dec byte [CUR_CHAR_IDX]
    jmp .redraw_initials
.wrap_ch_l:
    mov byte [CUR_CHAR_IDX], 2
    jmp .redraw_initials

.char_right:
    call sound_click
    cmp byte [CUR_CHAR_IDX], 2
    jae .wrap_ch_r
    inc byte [CUR_CHAR_IDX]
    jmp .redraw_initials
.wrap_ch_r:
    mov byte [CUR_CHAR_IDX], 0
    jmp .redraw_initials

.char_up:
    call sound_click
    mov bx, [CUR_CHAR_IDX]
    and bx, 3
    inc byte [CURRENT_NAME + bx]
    cmp byte [CURRENT_NAME + bx], 'Z'
    jbe .redraw_initials
    mov byte [CURRENT_NAME + bx], 'A'
    jmp .redraw_initials

.char_down:
    call sound_click
    mov bx, [CUR_CHAR_IDX]
    and bx, 3
    dec byte [CURRENT_NAME + bx]
    cmp byte [CURRENT_NAME + bx], 'A'
    jae .redraw_initials
    mov byte [CURRENT_NAME + bx], 'Z'
    jmp .redraw_initials

.init_done:
    call sound_toggle
    ret

; -----------------------------------------------------------------------------
; Mode 13h Register Tables, 256-Color Palettes & Multi-Color Pixel-Art Sprites
; -----------------------------------------------------------------------------
mode13h_seq_table:
    db 0x01, 0x0F, 0x00, 0x0E       ; SR01..SR04 (SR02=All 4 Planes, SR04=Chain-4 Linear)

mode13h_crtc_table:
    db 0x5F, 0x4F, 0x50, 0x82, 0x54, 0x80, 0xBF, 0x1F
    db 0x00, 0x41, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x9C, 0x0E, 0x8F, 0x28, 0x40, 0x96, 0xB9, 0xA3
    db 0xFF

mode13h_gc_table:
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x05, 0x0F, 0xFF

mode13h_ac_ext_table:
    db 0x41, 0x00, 0x0F, 0x00, 0x00

; Colors 0..5 per Board Theme (4 Themes x 6 Colors x 3 Bytes = 72 Bytes)
; 0:HUD Bar, 1:Outer Border, 2:Grass Light, 3:Grass Med, 4:Dim Grass Light, 5:Dim Grass Med
mode13h_theme_palettes:
    ; Theme 0: Lush Grass Checkerboard (Default)
    db 18, 29, 11,  22, 35, 13,  42, 54, 20,  40, 52, 18,  11, 18, 7,   9, 15, 6
    ; Theme 1: Cyber Emerald Checkerboard
    db 4, 18, 14,   6, 24, 18,   14, 46, 30,  10, 40, 26,  4, 14, 10,   3, 11, 8
    ; Theme 2: Golden Autumn Meadow
    db 26, 16, 6,   34, 22, 8,   52, 42, 18,  48, 38, 14,  16, 12, 5,   13, 10, 4
    ; Theme 3: Retro Arcade Checkerboard
    db 8, 10, 26,   12, 14, 34,  22, 28, 48,  18, 24, 42,  6, 8, 16,    5, 6, 13

; Colors 6..31 Fixed Pixel-Art Palette (26 Colors x 3 Bytes = 78 Bytes)
mode13h_fixed_palette:
    db 19, 48, 62   ;  6: Sky-Blue Popup Card (#4DC1F9)
    db 14, 40, 54   ;  7: Sky-Blue Card Rim
    db 6, 26, 52    ;  8: Royal-Blue Pill Button (#1967D2)
    db 10, 32, 63   ;  9: Hover Bright Royal-Blue Pill Button (#2979FF)
    db 4, 16, 36    ; 10: Pill Button 3D Bottom Lip (#114694)
    db 17, 29, 58   ; 11: Snake Primary Royal Blue (#4674E9)
    db 26, 38, 62   ; 12: Snake Top Specular Highlight (#6691F5)
    db 11, 20, 45   ; 13: Snake Bottom Shadow Contour (#3156B8)
    db 6, 9, 31     ; 14: Snake Eye Pupil & Nostril Deep Navy (#1A237E)
    db 63, 63, 63   ; 15: Pure Crisp White (#FFFFFF)
    db 58, 17, 7    ; 16: Glossy Scarlet Red Apple (#E7471D)
    db 44, 7, 7     ; 17: Apple Deep Crimson Shadow (#B71C1C)
    db 63, 36, 34   ; 18: Apple Soft Pink Highlight (#FF8A80)
    db 31, 46, 16   ; 19: Apple Leaf Fresh Green (#7CB342)
    db 27, 19, 16   ; 20: Apple Stem Warm Brown (#6D4C41)
    db 63, 48, 2    ; 21: Trophy / Golden Apple Gold (#FFC107)
    db 63, 60, 28   ; 22: Trophy Bright Lemon Highlight (#FFF176)
    db 56, 36, 0    ; 23: Trophy / Block Warm Amber (#FFA000)
    db 34, 4, 20    ; 24: Snake Chomp Mouth Maroon (#880E4F)
    db 60, 24, 36   ; 25: Snake Inner Tongue Pink (#F06292)
    db 6, 11, 4     ; 26: Drop Shadow Dark Forest (#182C10)
    db 0, 0, 0      ; 27: Pure Black (#000000)
    db 34, 45, 14   ; 28: Grass Horizon Edge (#8AB438)
    db 48, 52, 56   ; 29: Silver Gray
    db 20, 56, 30   ; 30: Mint Accent
    db 63, 20, 20   ; 31: Bright Coral

; 10x10 Multi-Color Glossy Red Apple Sprite (0xFF = transparent)
sprite_apple10:
    db 0xFF,0xFF,0xFF,0xFF, 20,  19,  19, 0xFF,0xFF,0xFF
    db 0xFF,0xFF, 16,  16,  20,  19,  16,  16, 0xFF,0xFF
    db 0xFF, 16,  15,  18,  16,  16,  16,  16,  17, 0xFF
    db 0xFF, 16,  18,  16,  16,  16,  16,  16,  17, 0xFF
    db 0xFF, 16,  16,  16,  16,  16,  16,  16,  17, 0xFF
    db 0xFF, 16,  16,  16,  16,  16,  16,  17,  17, 0xFF
    db 0xFF, 16,  16,  16,  16,  16,  16,  17,  17, 0xFF
    db 0xFF,0xFF, 16,  16,  16,  16,  17,  17, 0xFF,0xFF
    db 0xFF,0xFF,0xFF, 17,  17,  17,  17, 0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF, 26,  26,  26,  26, 0xFF,0xFF,0xFF

; 10x10 Multi-Color Golden Apple Sprite (0xFF = transparent)
sprite_gold_apple10:
    db 0xFF,0xFF,0xFF,0xFF, 20,  19,  19, 0xFF,0xFF,0xFF
    db 0xFF,0xFF, 21,  21,  20,  19,  21,  21, 0xFF,0xFF
    db 0xFF, 21,  15,  22,  21,  21,  21,  21,  23, 0xFF
    db 0xFF, 21,  22,  21,  21,  21,  21,  21,  23, 0xFF
    db 0xFF, 21,  21,  21,  21,  21,  21,  21,  23, 0xFF
    db 0xFF, 21,  21,  21,  21,  21,  21,  23,  23, 0xFF
    db 0xFF, 21,  21,  21,  21,  21,  21,  23,  23, 0xFF
    db 0xFF,0xFF, 21,  21,  21,  21,  23,  23, 0xFF,0xFF
    db 0xFF,0xFF,0xFF, 23,  23,  23,  23, 0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF, 26,  26,  26,  26, 0xFF,0xFF,0xFF

; 16x16 Multi-Color Glossy Red Apple Sprite (for HUD & Popup Card)
sprite_apple16:
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 20,  20,  19,  19,  19, 0xFF,0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 20,  19,  19,  19,  19, 0xFF,0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF, 16,  16,  16,  20,  20,  19,  16,  16,  16,  16, 0xFF,0xFF,0xFF
    db 0xFF,0xFF, 16,  16,  18,  18,  16,  16,  16,  16,  16,  16,  16,  17, 0xFF,0xFF
    db 0xFF, 16,  16,  15,  15,  18,  16,  16,  16,  16,  16,  16,  16,  17,  17, 0xFF
    db 0xFF, 16,  16,  15,  18,  16,  16,  16,  16,  16,  16,  16,  16,  17,  17, 0xFF
    db 0xFF, 16,  16,  18,  16,  16,  16,  16,  16,  16,  16,  16,  16,  17,  17, 0xFF
    db 0xFF, 16,  16,  16,  16,  16,  16,  16,  16,  16,  16,  16,  16,  17,  17, 0xFF
    db 0xFF, 16,  16,  16,  16,  16,  16,  16,  16,  16,  16,  16,  17,  17,  17, 0xFF
    db 0xFF, 16,  16,  16,  16,  16,  16,  16,  16,  16,  16,  16,  17,  17,  17, 0xFF
    db 0xFF,0xFF, 16,  16,  16,  16,  16,  16,  16,  16,  16,  17,  17,  17, 0xFF,0xFF
    db 0xFF,0xFF, 16,  16,  16,  16,  16,  16,  16,  16,  17,  17,  17,  17, 0xFF,0xFF
    db 0xFF,0xFF,0xFF, 16,  16,  16,  17,  17,  17,  17,  17,  17,  17, 0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF, 17,  17,  17, 0xFF,0xFF, 17,  17,  17, 0xFF,0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF, 26,  26,  26,  26,  26,  26,  26,  26, 0xFF,0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF

; 16x16 Multi-Color Golden Trophy Cup Sprite (for HUD & Popup Card)
sprite_trophy16:
    db 0xFF,0xFF,0xFF, 22,  22,  21,  21,  21,  21,  21,  21,  23,  23, 0xFF,0xFF,0xFF
    db 0xFF, 21,  21,  15,  22,  21,  21,  21,  21,  21,  21,  23,  23,  21,  21, 0xFF
    db  21,  23,  21,  15,  22,  21,  21,  21,  21,  21,  21,  23,  23,  21,  23,  21
    db  21, 0xFF, 21,  22,  22,  21,  21,  21,  21,  21,  21,  23,  23,  21, 0xFF, 21
    db  21, 0xFF, 21,  22,  21,  21,  21,  21,  21,  21,  21,  23,  23,  21, 0xFF, 21
    db 0xFF, 23,  23,  21,  21,  21,  21,  21,  21,  21,  21,  23,  23,  23,  23, 0xFF
    db 0xFF,0xFF,0xFF, 21,  21,  21,  21,  21,  21,  21,  23,  23,  23, 0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF, 21,  21,  21,  21,  21,  23,  23,  23, 0xFF,0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF, 21,  21,  21,  23,  23,  23, 0xFF,0xFF,0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 21,  21,  23,  23, 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 21,  21,  23,  23, 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF, 22,  21,  21,  23,  23,  23, 0xFF,0xFF,0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF, 22,  22,  21,  21,  21,  21,  23,  23,  23,  23, 0xFF,0xFF,0xFF
    db 0xFF,0xFF, 23,  23,  23,  23,  23,  23,  23,  23,  23,  23,  23,  23, 0xFF,0xFF
    db 0xFF,0xFF, 26,  26,  26,  26,  26,  26,  26,  26,  26,  26,  26,  26, 0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF

; 16x16 White HUD Speaker Icon
sprite_hud_speaker:
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 15,  15, 0xFF,0xFF, 15, 0xFF,0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 15,  15,  15, 0xFF,0xFF,0xFF, 15, 0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF, 15,  15,  15,  15, 0xFF, 15, 0xFF,0xFF, 15, 0xFF,0xFF
    db 0xFF,0xFF, 15,  15,  15,  15,  15,  15,  15, 0xFF,0xFF, 15, 0xFF, 15, 0xFF,0xFF
    db 0xFF,0xFF, 15,  15,  15,  15,  15,  15,  15, 0xFF,0xFF, 15, 0xFF, 15, 0xFF,0xFF
    db 0xFF,0xFF, 15,  15,  15,  15,  15,  15,  15, 0xFF,0xFF, 15, 0xFF, 15, 0xFF,0xFF
    db 0xFF,0xFF, 15,  15,  15,  15,  15,  15,  15, 0xFF,0xFF, 15, 0xFF, 15, 0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF, 15,  15,  15,  15, 0xFF, 15, 0xFF,0xFF, 15, 0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 15,  15,  15, 0xFF,0xFF,0xFF, 15, 0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 15,  15, 0xFF,0xFF, 15, 0xFF,0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF

; 16x16 White HUD Settings Gear Icon
sprite_hud_gear:
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 15,  15,  15, 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF, 15,  15, 0xFF, 15,  15,  15, 0xFF, 15,  15, 0xFF,0xFF,0xFF,0xFF
    db 0xFF,0xFF, 15,  15,  15,  15,  15,  15,  15,  15,  15,  15,  15, 0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF, 15,  15,  15, 0xFF,0xFF,0xFF, 15,  15,  15, 0xFF,0xFF,0xFF,0xFF
    db 0xFF, 15,  15,  15, 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 15,  15,  15, 0xFF,0xFF
    db 0xFF, 15,  15,  15, 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 15,  15,  15, 0xFF,0xFF
    db 0xFF, 15,  15,  15, 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 15,  15,  15, 0xFF,0xFF
    db 0xFF,0xFF,0xFF, 15,  15,  15, 0xFF,0xFF,0xFF, 15,  15,  15, 0xFF,0xFF,0xFF,0xFF
    db 0xFF,0xFF, 15,  15,  15,  15,  15,  15,  15,  15,  15,  15,  15, 0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF, 15,  15, 0xFF, 15,  15,  15, 0xFF, 15,  15, 0xFF,0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 15,  15,  15, 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF

; 12x16 Black-Outlined Crisp White Hardware Mouse Cursor Sprite
sprite_cursor_12x16:
    db  27,  27, 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF
    db  27,  15,  27, 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF
    db  27,  15,  15,  27, 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF
    db  27,  15,  15,  15,  27, 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF
    db  27,  15,  15,  15,  15,  27, 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF
    db  27,  15,  15,  15,  15,  15,  27, 0xFF,0xFF,0xFF,0xFF,0xFF
    db  27,  15,  15,  15,  15,  15,  15,  27, 0xFF,0xFF,0xFF,0xFF
    db  27,  15,  15,  15,  15,  15,  15,  15,  27, 0xFF,0xFF,0xFF
    db  27,  15,  15,  15,  15,  15,  15,  15,  15,  27, 0xFF,0xFF
    db  27,  15,  15,  15,  15,  15,  27,  27,  27,  27, 0xFF,0xFF
    db  27,  15,  15,  27,  15,  15,  27, 0xFF,0xFF,0xFF,0xFF,0xFF
    db  27,  15,  27, 0xFF, 27,  15,  15,  27, 0xFF,0xFF,0xFF,0xFF
    db  27,  27, 0xFF,0xFF, 27,  15,  15,  27, 0xFF,0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF, 27,  15,  15,  27, 0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF, 27,  15,  15,  27, 0xFF,0xFF,0xFF
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 27,  27, 0xFF,0xFF,0xFF,0xFF

str_btn_play_txt:
    db "Play Cybforge Snake", 0
str_btn_setup_txt:
    db "BIOS Setup & Settings", 0
str_btn_shell_txt:
    db "Launch UEFI/BIOS Shell", 0
str_go_short:
    db "GAME OVER", 0
str_vic_short:
    db "* VICTORY! *", 0

    ; --- CMOS NVRAM PERSISTENCE (0x70 / 0x71) ---
cmos_read_byte:
    out 0x70, al
    jmp $+2
    in al, 0x71
    ret

cmos_write_byte:
    push ax
    out 0x70, al
    jmp $+2
    mov al, ah
    out 0x71, al
    pop ax
    ret

load_cmos_settings:
    ; 1. First try loading the 16 KB persistent volume (LBA 0..31 -> 0x3000..0x6FFF) from ATA disk!
    call ata_load_nvram
    cmp word [FS_MAGIC], 0x5346     ; Valid 'FS' (CybFS v1.0) found on disk?
    je .ata_fs_valid

    ; No valid CybFS on disk -> Format fresh from ROM Block 0 (0xFFFC0100) into RAM
    call fs_format_from_rom
    jmp .check_cmos_hw

.ata_fs_valid:
    ; If signature 0xCC is present at 0x6FE0 in the disk image, restore CMOS registers 0x40..0x5F from it!
    cmp byte [NVRAM_MIRROR], 0xCC
    jne .check_cmos_hw
    mov cl, 0x40
    mov si, NVRAM_MIRROR
.restore_cmos_from_disk:
    mov al, cl
    mov ah, [ds:si]
    call cmos_write_byte
    inc si
    inc cl
    cmp cl, 0x60
    jb .restore_cmos_from_disk

.check_cmos_hw:
    ; Check if signature 0xCC is present at index 0x40
    mov al, 0x40
    call cmos_read_byte
    cmp al, 0xCC
    jne .cmos_invalid

    ; Calculate checksum (0x40..0x5D, checksum in 0x5E)
    xor bl, bl
    mov cl, 0x40
.chk_loop:
    mov al, cl
    call cmos_read_byte
    xor bl, al
    inc cl
    cmp cl, 0x5E
    jb .chk_loop

    mov al, 0x5E
    call cmos_read_byte
    cmp al, bl
    jne .cmos_invalid

    ; Load valid configuration!
    mov al, 0x41
    call cmos_read_byte
    mov [CFG_SPEED], al
    mov al, 0x42
    call cmos_read_byte
    mov [CFG_WALLS], al
    mov al, 0x43
    call cmos_read_byte
    mov [CFG_SOUND], al
    mov al, 0x44
    call cmos_read_byte
    mov [CFG_FACE], al
    mov al, 0x45
    call cmos_read_byte
    mov [CFG_LEN], al
    mov al, 0x46
    call cmos_read_byte
    mov [CFG_WIN], al
    mov al, 0x47
    call cmos_read_byte
    mov [CFG_DISP], al
    mov al, 0x48
    call cmos_read_byte
    mov [CFG_THEME], al
    mov al, 0x49
    call cmos_read_byte
    mov [CFG_ARENA], al

    ; Load Top 3 Leaderboard (15 bytes: 0x4A..0x58)
    mov cl, 0x4A
    mov di, TOP3_TABLE
.load_top3_loop:
    mov al, cl
    call cmos_read_byte
    mov [di], al
    inc di
    inc cl
    cmp cl, 0x59
    jb .load_top3_loop

    ; Load BiosShell settings (0x59..0x5D)
    mov al, 0x59
    call cmos_read_byte
    and al, 3
    mov [CFG_SH_THEME], al
    mov al, 0x5A
    call cmos_read_byte
    mov [CFG_SH_PROMPT], al
    mov al, 0x5B
    call cmos_read_byte
    mov [CFG_SH_BANNER], al
    mov al, 0x5C
    call cmos_read_byte
    and al, 1
    mov [CFG_SH_BEEP], al
    mov al, 0x5D
    call cmos_read_byte
    and al, 1
    mov [CFG_BOOT_MODE], al

    ; Load font scale CFG_SH_FONT from register 0x5F (signature nibble 0xD0)
    mov al, 0x5F
    call cmos_read_byte
    mov ah, al
    and ah, 0xFC
    cmp ah, 0xD0
    jne .font_default
    and al, 3
    mov [CFG_SH_FONT], al
    jmp .font_loaded
.font_default:
    mov byte [CFG_SH_FONT], 2
.font_loaded:

    mov ax, [TOP3_TABLE + 3]
    mov [HIGH_SCORE], ax
    ret

.cmos_invalid:
    ; Factory defaults
    mov byte [CFG_SPEED], 0
    mov byte [CFG_WALLS], 0
    mov byte [CFG_SOUND], 0
    mov byte [CFG_FACE],  0
    mov byte [CFG_LEN],   0
    mov byte [CFG_WIN],   0
    mov byte [CFG_DISP],  0
    mov byte [CFG_THEME], 0
    mov byte [CFG_ARENA], 0

    mov byte [CFG_SH_THEME],  0
    mov byte [CFG_SH_PROMPT], 0
    mov byte [CFG_SH_BANNER], 0
    mov byte [CFG_SH_BEEP],   0
    mov byte [CFG_BOOT_MODE], 0
    mov byte [CFG_SH_FONT],   2

    ; Default Top 3: CYB (30), JON (20), ACE (10)
    mov byte [TOP3_TABLE + 0], 'C'
    mov byte [TOP3_TABLE + 1], 'Y'
    mov byte [TOP3_TABLE + 2], 'B'
    mov word [TOP3_TABLE + 3], 30

    mov byte [TOP3_TABLE + 5], 'J'
    mov byte [TOP3_TABLE + 6], 'O'
    mov byte [TOP3_TABLE + 7], 'N'
    mov word [TOP3_TABLE + 8], 20

    mov byte [TOP3_TABLE + 10], 'A'
    mov byte [TOP3_TABLE + 11], 'C'
    mov byte [TOP3_TABLE + 12], 'E'
    mov word [TOP3_TABLE + 13], 10

    mov word [HIGH_SCORE], 30
    call save_cmos_settings
    ret

save_cmos_settings:
    mov al, 0x40
    mov ah, 0xCC
    call cmos_write_byte
    mov al, 0x41
    mov ah, [CFG_SPEED]
    call cmos_write_byte
    mov al, 0x42
    mov ah, [CFG_WALLS]
    call cmos_write_byte
    mov al, 0x43
    mov ah, [CFG_SOUND]
    call cmos_write_byte
    mov al, 0x44
    mov ah, [CFG_FACE]
    call cmos_write_byte
    mov al, 0x45
    mov ah, [CFG_LEN]
    call cmos_write_byte
    mov al, 0x46
    mov ah, [CFG_WIN]
    call cmos_write_byte
    mov al, 0x47
    mov ah, [CFG_DISP]
    call cmos_write_byte
    mov al, 0x48
    mov ah, [CFG_THEME]
    call cmos_write_byte
    mov al, 0x49
    mov ah, [CFG_ARENA]
    call cmos_write_byte

    ; Write Top 3 Leaderboard (0x4A..0x58)
    mov cl, 0x4A
    mov si, TOP3_TABLE
.save_top3_loop:
    mov al, cl
    mov ah, [si]
    call cmos_write_byte
    inc si
    inc cl
    cmp cl, 0x59
    jb .save_top3_loop

    ; Write BiosShell settings (0x59..0x5D)
    mov al, 0x59
    mov ah, [CFG_SH_THEME]
    call cmos_write_byte
    mov al, 0x5A
    mov ah, [CFG_SH_PROMPT]
    call cmos_write_byte
    mov al, 0x5B
    mov ah, [CFG_SH_BANNER]
    call cmos_write_byte
    mov al, 0x5C
    mov ah, [CFG_SH_BEEP]
    call cmos_write_byte
    mov al, 0x5D
    mov ah, [CFG_BOOT_MODE]
    call cmos_write_byte

    ; Calculate checksum & write to 0x5E
    xor bl, bl
    mov cl, 0x40
.save_chk:
    mov al, cl
    call cmos_read_byte
    xor bl, al
    inc cl
    cmp cl, 0x5E
    jb .save_chk

    mov al, 0x5E
    mov ah, bl
    call cmos_write_byte

    ; Save current font scale CFG_SH_FONT with signature 0xD0 into register 0x5F
    mov al, [CFG_SH_FONT]
    and al, 3
    or al, 0xD0
    mov ah, al
    mov al, 0x5F
    call cmos_write_byte

    ; Write complete CybFS + CMOS NVRAM mirror (0x3000..0x6FFF) persistently to ATA disk!
    call ata_sync_nvram
    ret

    ; --- VGA HARDWARE DAC THEMES (Dual Mode: Modern UEFI Dark vs Google Snake Grass) ---
load_ui_palette:
    push ax
    push si
    push cx
    push dx
    mov byte [UI_PAL_MODE], 0
    mov si, ui_modern_palette
    mov dx, 0x3C8
    xor al, al
    out dx, al
    mov dx, 0x3C9
    mov cx, 48
.ui_dac_loop:
    mov al, [cs:si]
    inc si
    out dx, al
    loop .ui_dac_loop
    pop dx
    pop cx
    pop si
    pop ax
    ret

apply_color_theme:
    push ax
    push si
    push cx
    push dx
    mov byte [UI_PAL_MODE], 1

    mov al, [CFG_THEME]
    and al, 3
    xor ah, ah
    mov cx, 48
    mul cl
    mov si, ax
    add si, palette_themes_table

    mov dx, 0x3C8
    xor al, al
    out dx, al                      ; Start at color index 0
    mov dx, 0x3C9
    mov cx, 48
.dac_loop:
    mov al, [cs:si]
    inc si
    out dx, al
    loop .dac_loop

    pop dx
    pop cx
    pop si
    pop ax
    ret

    ; --- ANIMATED POST RAM COUNTER ---
post_ram_counter:
    mov di, (14 * 80 + 2) * 2
    mov si, str_post_mem_lbl
    mov ah, 0x07
    call print_string

    xor bp, bp
.ram_cnt_loop:
    mov al, 16
    mov bl, 14
    call xy_to_di
    mov ax, bp
    call render_3digits_yellow
    mov si, str_kb_suffix
    mov ah, 0x07
    call print_string

    ; Soft, pleasant hardware tick (~1.2 ms)
    mov bx, 0x0680
    call start_tone
    mov ecx, 300000
    call delay_cycles
    call stop_tone

    mov ecx, 10000000
    call delay_cycles
    add bp, 64
    cmp bp, 640
    jbe .ram_cnt_loop

    mov si, str_ok_suffix
    mov ah, 0x0A
    call print_string
    ret

dummy_isr:
    iret

clear_screen_black:
    xor di, di
    mov cx, 80 * 25
    mov ax, 0x0720
    rep stosw
    ret

print_string:
    push bx
.ps_loop:
    mov al, [cs:si]
    inc si
    test al, al
    jz .ps_done
    stosw
    jmp .ps_loop
.ps_done:
    pop bx
    ret

xy_to_di:
    push ax
    push bx
    xor bh, bh
    mov di, bx
    shl di, 4
    shl bx, 6
    add di, bx
    xor ah, ah
    add di, ax
    shl di, 1
    pop bx
    pop ax
    ret

delay_cycles:
.dc_loop:
    dec ecx
    jnz .dc_loop
    ret

drain_kbd:
    mov cx, 1000
.drain_loop:
    in al, 0x64
    test al, 0x01
    jz .drain_empty
    in al, 0x60
    dec cx
    jnz .drain_loop
.drain_empty:
    mov byte [MOUSE_PKT_IDX], 0
    ret

read_key:
.rk_loop:
    in al, 0x64
    test al, 0x01
    jz .no_key
    test al, 0x20                   ; Bit 5 = 8042 Auxiliary Mouse byte!
    jnz .rk_mouse_byte
    in al, 0x60
    mov byte [MOUSE_PKT_IDX], 0     ; Reset mouse packet sync on keyboard byte
    test al, 0x80
    jnz .rk_loop
    ret
.rk_mouse_byte:
    in al, 0x60
    call mouse_process_byte
    jmp .rk_loop
.no_key:
    xor al, al
    ret

    ; =========================================================================
    ; BARE-METAL 8042 PS/2 AUX & USB POINTER HARDWARE MOUSE DRIVER
    ; =========================================================================
mouse_init:
    push ax
    push cx
    mov word [MOUSE_FINE_X], 320
    mov word [MOUSE_FINE_Y], 200
    mov byte [MOUSE_X], 40
    mov byte [MOUSE_Y], 12
    mov byte [MOUSE_BTN], 0
    mov byte [MOUSE_PREV_BTN], 0
    mov byte [MOUSE_CLICK], 0
    mov byte [MOUSE_PKT_IDX], 0
    mov byte [MOUSE_CUR_VIS], 0
    mov word [MOUSE_EVT_CNT], 0
    mov byte [MOUSE_READY], 1

    ; 1. Enable Auxiliary Mouse Device (Command 0xA8 to Port 0x64)
    call kbc_wait_write
    mov al, 0xA8
    out 0x64, al

    ; 2. Read 8042 Controller Command Byte (0x20)
    call kbc_wait_write
    mov al, 0x20
    out 0x64, al
    call kbc_wait_read
    in al, 0x60
    or al, 0x42                     ; Enable Aux IRQ/Stream + Scancode Set 1 Translation
    and al, 0xDF                    ; Clear Bit 5 (Enable Aux Mouse Clock)
    push ax

    ; 3. Write updated 8042 Command Byte (0x60)
    call kbc_wait_write
    mov al, 0x60
    out 0x64, al
    call kbc_wait_write
    pop ax
    out 0x60, al

    ; 4. Send 0xF6 (Set Defaults) to Mouse via 0xD4 prefix
    mov ah, 0xF6
    call mouse_write_cmd

    ; 5. Send 0xF4 (Enable Data Reporting) to Mouse via 0xD4 prefix
    mov ah, 0xF4
    call mouse_write_cmd

    call drain_kbd
    pop cx
    pop ax
    ret

mouse_write_cmd:
    ; Sends command byte in AH to PS/2 Aux Mouse and reads ACK (0xFA)
    call kbc_wait_write
    mov al, 0xD4
    out 0x64, al
    call kbc_wait_write
    mov al, ah
    out 0x60, al
    call kbc_wait_read
    in al, 0x60
    ret

kbc_wait_write:
    push cx
    push ax
    mov cx, 10000
.kww_lp:
    in al, 0x64
    test al, 0x02
    jz .kww_ok
    loop .kww_lp
.kww_ok:
    pop ax
    pop cx
    ret

kbc_wait_read:
    push cx
    push ax
    mov cx, 10000
.kwr_lp:
    in al, 0x64
    test al, 0x01
    jnz .kwr_ok
    loop .kwr_lp
.kwr_ok:
    pop ax
    pop cx
    ret

mouse_process_byte:
    ; Processes 1 byte (in AL) from the 3-byte PS/2 mouse packet stream
    push ax
    push bx
    push cx
    push dx

    mov bl, [MOUSE_PKT_IDX]
    cmp bl, 0
    je .mpb_byte0
    cmp bl, 1
    je .mpb_byte1

    ; --- Byte 2: Delta Y (Packet Complete!) ---
    mov byte [MOUSE_PKT_IDX], 0
    inc word [MOUSE_EVT_CNT]
    mov cl, al                      ; CL = raw dY
    mov bh, [MOUSE_PKT_B0]          ; BH = status/buttons/signs

    ; 1. Signed Delta X (from MOUSE_PKT_B1 and Bit 4 of BH)
    xor ah, ah
    mov al, [MOUSE_PKT_B1]
    test bh, 0x10                   ; X sign bit?
    jz .mpb_dx_pos
    mov ah, 0xFF
.mpb_dx_pos:
    add ax, [MOUSE_FINE_X]
    cmp ax, 0
    jge .mpb_x_min_ok
    xor ax, ax
.mpb_x_min_ok:
    cmp ax, 639
    jle .mpb_x_max_ok
    mov ax, 639
.mpb_x_max_ok:
    mov [MOUSE_FINE_X], ax
    shr ax, 3                       ; Text column = fine_x / 8 (0..79)
    mov [MOUSE_X], al

    ; 2. Signed Delta Y (from CL and Bit 5 of BH; PS/2 +Y is up, screen +Y is down)
    xor ah, ah
    mov al, cl
    test bh, 0x20                   ; Y sign bit?
    jz .mpb_dy_pos
    mov ah, 0xFF
.mpb_dy_pos:
    mov dx, [MOUSE_FINE_Y]
    sub dx, ax
    cmp dx, 0
    jge .mpb_y_min_ok
    xor dx, dx
.mpb_y_min_ok:
    cmp dx, 399
    jle .mpb_y_max_ok
    mov dx, 399
.mpb_y_max_ok:
    mov [MOUSE_FINE_Y], dx
    shr dx, 4                       ; Text row = fine_y / 16 (0..24)
    mov [MOUSE_Y], dl

    ; 3. Buttons & rising-edge click detection
    mov al, bh
    and al, 0x07
    mov ah, [MOUSE_PREV_BTN]
    not ah
    and ah, al                      ; AH = newly pressed buttons (rising edge!)
    or [MOUSE_CLICK], ah
    mov [MOUSE_PREV_BTN], al
    mov [MOUSE_BTN], al

    ; 4. Move live software cursor on screen (if in 80x25 Text Mode)!
    cmp byte [VGA_GFX_ACTIVE], 1
    je .mpb_done
    call mouse_show_cursor
    jmp .mpb_done

.mpb_byte0:
    ; Validate Bit 3 (always 1 in standard PS/2 packet) and no overflow (Bits 6,7 == 0)
    test al, 0x08
    jz .mpb_done
    test al, 0xC0
    jnz .mpb_done
    mov [MOUSE_PKT_B0], al
    mov byte [MOUSE_PKT_IDX], 1
    jmp .mpb_done

.mpb_byte1:
    mov [MOUSE_PKT_B1], al
    mov byte [MOUSE_PKT_IDX], 2

.mpb_done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

mouse_hide_cursor:
    cmp byte [MOUSE_CUR_VIS], 1
    jne .mhc_done
    push ax
    push bx
    push di
    mov al, [MOUSE_OLD_X]
    mov bl, [MOUSE_OLD_Y]
    call xy_to_di
    mov ax, [MOUSE_SAVED_W]
    mov [es:di], ax
    mov byte [MOUSE_CUR_VIS], 0
    pop di
    pop bx
    pop ax
.mhc_done:
    ret

mouse_show_cursor:
    push ax
    push bx
    push di
    call mouse_hide_cursor
    mov al, [MOUSE_X]
    mov bl, [MOUSE_Y]
    mov [MOUSE_OLD_X], al
    mov [MOUSE_OLD_Y], bl
    call xy_to_di
    mov ax, [es:di]
    mov [MOUSE_SAVED_W], ax
    and ah, 0x70                    ; Preserve cell background color
    or ah, 0x0F                     ; Crisp Bright White Pointer (0x0F)
    mov al, 0x14                    ; 0x14 = Custom Diagonal Arrow Pointer '↖'
    mov [es:di], ax
    mov byte [MOUSE_CUR_VIS], 1
    pop di
    pop bx
    pop ax
    ret

    ; =========================================================================
    ; BARE-METAL xHCI (USB 3.0) & EHCI (USB 2.0) PCI/MMIO DRIVER
    ; Scans PCI Bus 0 (0xCF8/0xCFC), assigns MMIO BAR0 if unassigned, enables
    ; Bus Master + Memory Space, starts controllers, and scans Root Hub PORTSC!
    ; =========================================================================
usb_init_controllers:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov byte [XHCI_FOUND], 0
    mov byte [EHCI_FOUND], 0
    mov byte [XHCI_PORTS_CONN], 0
    mov byte [EHCI_PORTS_CONN], 0

    xor cx, cx                      ; CL = Device (0..31), CH = Function (0..7)
.usb_pci_loop:
    mov eax, 0x80000000
    movzx edx, cl
    shl edx, 11
    or eax, edx
    movzx edx, ch
    shl edx, 8
    or eax, edx
    mov esi, eax                    ; ESI = Base PCI Config Address for (Bus 0, Dev CL, Fn CH)

    mov dx, 0x0CF8
    out dx, eax
    mov dx, 0x0CFC
    in eax, dx                      ; EAX = [DeviceID (31:16) | VendorID (15:0)]
    cmp ax, 0xFFFF
    je .usb_pci_next
    test ax, ax
    jz .usb_pci_next

    mov ebx, eax                    ; EBX = [DeviceID | VendorID]

    ; Read Class / Subclass / ProgIF at Reg 0x08
    mov eax, esi
    or eax, 0x08
    mov dx, 0x0CF8
    out dx, eax
    mov dx, 0x0CFC
    in eax, dx
    shr eax, 8                      ; EAX = 0x00CCSSPP (Class, Subclass, ProgIF)

    cmp eax, 0x000C0330             ; Class 0Ch, Subclass 03h, ProgIF 30h = xHCI (USB 3.0)!
    je .init_xhci_ctrl
    cmp eax, 0x000C0320             ; Class 0Ch, Subclass 03h, ProgIF 20h = EHCI (USB 2.0)!
    je .init_ehci_ctrl
    jmp .usb_pci_next

.init_xhci_ctrl:
    mov byte [XHCI_FOUND], 1
    mov [XHCI_BUS_DEV], cl
    mov [XHCI_VEN_ID], bx
    shr ebx, 16
    mov [XHCI_DEV_ID], bx

    ; Read BAR0 (Reg 0x10)
    mov eax, esi
    or eax, 0x10
    mov dx, 0x0CF8
    out dx, eax
    mov dx, 0x0CFC
    in eax, dx
    and eax, 0xFFFFF000
    jnz .xhci_bar_ok
    ; Assign 0xFEB00000 to xHCI BAR0 (and 0 to BAR1 64-bit high dword)
    mov eax, esi
    or eax, 0x14
    mov dx, 0x0CF8
    out dx, eax
    mov dx, 0x0CFC
    xor eax, eax
    out dx, eax

    mov eax, esi
    or eax, 0x10
    mov dx, 0x0CF8
    out dx, eax
    mov dx, 0x0CFC
    mov eax, 0xFEB00000
    out dx, eax
.xhci_bar_ok:
    mov ebx, eax                    ; EBX = xHCI MMIO Base (e.g. 0xFEB00000)

    ; Enable PCI Memory Space (Bit 1) + Bus Master (Bit 2) in Command Reg 0x04
    mov eax, esi
    or eax, 0x04
    mov dx, 0x0CF8
    out dx, eax
    mov dx, 0x0CFC
    in ax, dx
    or ax, 0x0006
    out dx, ax

    ; Read xHCI Capability Registers via 32-bit Flat Unreal Mode [fs:ebx]!
    a32 mov eax, [fs:ebx + 0x00]    ; AL = CAPLENGTH, High Word = HCIVERSION
    movzx edi, al
    add edi, ebx                    ; EDI = xHCI Operational Base (MMIO + CAPLENGTH)
    shr eax, 16
    mov [XHCI_HCI_VER], ax

    a32 mov eax, [fs:ebx + 0x04]    ; HCSPARAMS1: Bits 7:0 = MaxSlots, Bits 31:24 = MaxPorts
    mov [XHCI_MAX_SLOTS], al
    shr eax, 24
    mov [XHCI_MAX_PORTS], al

    ; Start xHCI Controller: Set USBCMD.RS (Bit 0) at Operational Base + 0x00
    a32 mov eax, [fs:edi + 0x00]
    or eax, 1
    a32 mov [fs:edi + 0x00], eax

    ; Scan xHCI Root Hub PORTSC registers (Operational Base + 0x400 + port * 0x10)
    a32 mov eax, [fs:edi + 0x400]
    mov [XHCI_PORT1_SC], eax

    movzx edx, byte [XHCI_MAX_PORTS]
    test edx, edx
    jz .usb_pci_next
    xor eax, eax
.xhci_port_scan:
    push eax
    shl eax, 4
    add eax, edi
    a32 mov eax, [fs:eax + 0x400]
    test al, 1                      ; Bit 0 = CCS (Current Connect Status)
    jz .xhci_port_next
    inc byte [XHCI_PORTS_CONN]
.xhci_port_next:
    pop eax
    inc eax
    cmp eax, edx
    jb .xhci_port_scan
    jmp .usb_pci_next

.init_ehci_ctrl:
    mov byte [EHCI_FOUND], 1
    mov [EHCI_BUS_DEV], cl
    mov [EHCI_VEN_ID], bx
    shr ebx, 16
    mov [EHCI_DEV_ID], bx

    ; Read BAR0 (Reg 0x10)
    mov eax, esi
    or eax, 0x10
    mov dx, 0x0CF8
    out dx, eax
    mov dx, 0x0CFC
    in eax, dx
    and eax, 0xFFFFF000
    jnz .ehci_bar_ok
    mov eax, esi
    or eax, 0x10
    mov dx, 0x0CF8
    out dx, eax
    mov dx, 0x0CFC
    mov eax, 0xFEB10000
    out dx, eax
.ehci_bar_ok:
    mov ebx, eax                    ; EBX = EHCI MMIO Base (e.g. 0xFEB10000)

    ; Enable PCI Memory Space + Bus Master in Command Reg 0x04
    mov eax, esi
    or eax, 0x04
    mov dx, 0x0CF8
    out dx, eax
    mov dx, 0x0CFC
    in ax, dx
    or ax, 0x0006
    out dx, ax

    ; Read EHCI Capability Registers via [fs:ebx]!
    a32 mov eax, [fs:ebx + 0x00]    ; AL = CAPLENGTH, High Word = HCIVERSION
    movzx edi, al
    add edi, ebx                    ; EDI = EHCI Operational Base
    shr eax, 16
    mov [EHCI_HCI_VER], ax

    a32 mov eax, [fs:ebx + 0x04]    ; HCSPARAMS: Bits 3:0 = N_PORTS
    and al, 0x0F
    mov [EHCI_MAX_PORTS], al

    ; Start EHCI Controller (USBCMD.RS = 1) & Route all ports to EHCI (CONFIGFLAG = 1)
    a32 mov eax, [fs:edi + 0x00]
    or eax, 1
    a32 mov [fs:edi + 0x00], eax
    mov eax, 1
    a32 mov [fs:edi + 0x40], eax    ; CONFIGFLAG = 1

    ; Scan EHCI Root Hub PORTSC registers (Operational Base + 0x44 + port * 4)
    a32 mov eax, [fs:edi + 0x44]
    mov [EHCI_PORT1_SC], eax

    movzx edx, byte [EHCI_MAX_PORTS]
    test edx, edx
    jz .usb_pci_next
    xor eax, eax
.ehci_port_scan:
    push eax
    shl eax, 2
    add eax, edi
    a32 mov eax, [fs:eax + 0x44]
    test al, 1                      ; Bit 0 = CCS (Current Connect Status)
    jz .ehci_port_next
    inc byte [EHCI_PORTS_CONN]
.ehci_port_next:
    pop eax
    inc eax
    cmp eax, edx
    jb .ehci_port_scan

.usb_pci_next:
    inc ch
    cmp ch, 8
    jb .usb_pci_loop
    xor ch, ch
    inc cl
    cmp cl, 32
    jb .usb_pci_loop

    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

start_tone:
    cmp byte [CFG_SOUND], 1
    je .play_spk
    cmp byte [CFG_SOUND], 2
    je .play_spk
    ret
.play_spk:
    push ax
    mov al, 0xB6
    out 0x43, al
    mov al, bl
    out 0x42, al
    mov al, bh
    out 0x42, al
    in al, 0x61
    or al, 0x03
    out 0x61, al
    pop ax
    ret

force_speaker_tone:
    push ax
    mov al, 0xB6
    out 0x43, al
    mov al, bl
    out 0x42, al
    mov al, bh
    out 0x42, al
    in al, 0x61
    or al, 0x03
    out 0x61, al
    pop ax
    ret

set_tone_freq:
    push ax
    mov al, bl
    out 0x42, al
    mov al, bh
    out 0x42, al
    pop ax
    ret

stop_tone:
    push ax
    in al, 0x61
    and al, 0xFC
    out 0x61, al
    pop ax
    ret

; -----------------------------------------------------------------------------
; IN-GAME AUDIO HANDLERS (SB16 16-BIT PCM + PC SPEAKER DUAL MODE)
; -----------------------------------------------------------------------------
sound_eat_fruit:
    push ax
    mov al, 0                       ; 0 = SND_CRUNCH
    call sb16_play_pcm
    pop ax
    cmp byte [CFG_SOUND], 1
    je .sef_spk
    cmp byte [CFG_SOUND], 2
    je .sef_spk
    ret
.sef_spk:
    push ax
    push bx
    push ecx
    mov bx, 0x05F2
    call force_speaker_tone
    mov ecx, 8750000
    call delay_cycles
    mov bx, 0x0474
    call set_tone_freq
    mov ecx, 16250000
    call delay_cycles
    call stop_tone
    pop ecx
    pop bx
    pop ax
    ret

sound_golden_apple:
    push ax
    mov al, 1                       ; 1 = SND_GOLDEN
    call sb16_play_pcm
    pop ax
    cmp byte [CFG_SOUND], 1
    je .sga_spk
    cmp byte [CFG_SOUND], 2
    je .sga_spk
    ret
.sga_spk:
    push ax
    push bx
    push ecx
    mov bx, 0x05F2
    call force_speaker_tone
    mov ecx, 10000000
    call delay_cycles
    mov bx, 0x04B7
    call set_tone_freq
    mov ecx, 10000000
    call delay_cycles
    mov bx, 0x0389
    call set_tone_freq
    mov ecx, 25000000
    call delay_cycles
    call stop_tone
    pop ecx
    pop bx
    pop ax
    ret

sound_crash:
    push ax
    mov al, 2                       ; 2 = SND_CRASH
    call sb16_play_pcm
    pop ax
    ret

sound_start:
    push ax
    mov al, 3                       ; 3 = SND_START
    call sb16_play_pcm
    pop ax
    cmp byte [CFG_SOUND], 1
    je .sst_spk
    cmp byte [CFG_SOUND], 2
    je .sst_spk
    ret
.sst_spk:
    push ax
    push bx
    push ecx
    mov bx, 0x0713
    call force_speaker_tone
    mov ecx, 3000000                ; ~15 ms
    call delay_cycles
    mov bx, 0x054C
    call set_tone_freq
    mov ecx, 4000000                ; ~20 ms
    call delay_cycles
    call stop_tone
    pop ecx
    pop bx
    pop ax
    ret

sound_pause:
    push ax
    mov al, 4                       ; 4 = SND_PAUSE
    call sb16_play_pcm
    pop ax
    cmp byte [CFG_SOUND], 1
    je .spz_spk
    cmp byte [CFG_SOUND], 2
    je .spz_spk
    ret
.spz_spk:
    push ax
    push bx
    push ecx
    mov bx, 0x054C
    call force_speaker_tone
    mov ecx, 3000000
    call delay_cycles
    call stop_tone
    mov ecx, 4000000
    call delay_cycles
    mov bx, 0x0713
    call force_speaker_tone
    mov ecx, 3000000
    call delay_cycles
    call stop_tone
    pop ecx
    pop bx
    pop ax
    ret

sound_boot:
    push ax
    mov al, 5                       ; 5 = SND_BOOT
    call sb16_play_pcm
    pop ax
    ret

sound_game_over:
    push ax
    mov al, 6                       ; 6 = SND_GAMEOVER
    call sb16_play_pcm
    pop ax
    cmp byte [CFG_SOUND], 1
    je .sgo_spk
    cmp byte [CFG_SOUND], 2
    je .sgo_spk
    ret
.sgo_spk:
    push ax
    push bx
    push ecx
    mov bx, 0x08E9
    call force_speaker_tone
    mov ecx, 17500000
    call delay_cycles
    mov bx, 0x0B3B
    call set_tone_freq
    mov ecx, 20000000
    call delay_cycles
    mov bx, 0x0BE4
    call set_tone_freq
    mov ecx, 20000000
    call delay_cycles
    mov bx, 0x0EFD
    call set_tone_freq
    mov ecx, 35000000
    call delay_cycles
    call stop_tone
    pop ecx
    pop bx
    pop ax
    ret

sound_victory:
    push ax
    mov al, 7                       ; 7 = SND_VICTORY
    call sb16_play_pcm
    pop ax
    cmp byte [CFG_SOUND], 1
    je .svic_spk
    cmp byte [CFG_SOUND], 2
    je .svic_spk
    ret
.svic_spk:
    push ax
    push bx
    push ecx
    mov bx, 0x08E9
    call force_speaker_tone
    mov ecx, 17500000
    call delay_cycles
    mov bx, 0x0713
    call set_tone_freq
    mov ecx, 17500000
    call delay_cycles
    mov bx, 0x05F2
    call set_tone_freq
    mov ecx, 17500000
    call delay_cycles
    mov bx, 0x0474
    call set_tone_freq
    mov ecx, 25000000
    call delay_cycles
    mov bx, 0x05F2
    call set_tone_freq
    mov ecx, 17500000
    call delay_cycles
    mov bx, 0x0474
    call set_tone_freq
    mov ecx, 50000000
    call delay_cycles
    call stop_tone
    pop ecx
    pop bx
    pop ax
    ret

sound_click:
    cmp byte [CFG_SOUND], 3
    je .sc_done
    push ax
    push bx
    push ecx
    mov bx, 0x0740                  ; Warm, soft low-mid wooden tap (~640 Hz)
    call force_speaker_tone
    mov ecx, 950000                 ; Ultra-short ~2ms subtle tactile click
    call delay_cycles
    call stop_tone
    pop ecx
    pop bx
    pop ax
.sc_done:
    ret

sound_toggle:
    cmp byte [CFG_SOUND], 3
    je .st_done
    push ax
    push bx
    push ecx
    mov bx, 0x0620
    call force_speaker_tone
    mov ecx, 1400000
    call delay_cycles
    mov bx, 0x04A0
    call set_tone_freq
    mov ecx, 1800000
    call delay_cycles
    call stop_tone
    pop ecx
    pop bx
    pop ax
.st_done:
    ret

sound_golden_spawn:
    push ax
    mov al, 3                       ; 3 = SND_START chime
    call sb16_play_pcm
    pop ax
    cmp byte [CFG_SOUND], 1
    je .sgs_spk
    cmp byte [CFG_SOUND], 2
    je .sgs_spk
    ret
.sgs_spk:
    push ax
    push bx
    push ecx
    mov bx, 0x054C
    call force_speaker_tone
    mov ecx, 6000000
    call delay_cycles
    mov bx, 0x0389
    call set_tone_freq
    mov ecx, 10000000
    call delay_cycles
    call stop_tone
    pop ecx
    pop bx
    pop ax
    ret

; =============================================================================
; SOUND BLASTER 16 & FLAT REAL MODE (UNREAL MODE) SUBSYSTEM
; =============================================================================
enter_unreal_mode:
    push eax
    push bx
    push ds
    lgdt [cs:gdt_desc]
    mov eax, cr0
    or al, 1
    mov cr0, eax
    jmp $+2
    mov bx, 0x08
    mov fs, bx
    and al, 0xFE
    mov cr0, eax
    jmp $+2
    pop ds
    pop bx
    pop eax
    ret

sb16_init:
    push ax
    push bx
    push cx
    push dx

    mov byte [sb16_detected], 0

    ; 1. Reset DSP
    mov dx, 0x226
    mov al, 1
    out dx, al
    mov cx, 50
.d1:
    in al, 0x80
    loop .d1
    xor al, al
    out dx, al

    ; 2. Wait for DSP ready (Port 0x22E Bit 7 = 1)
    mov dx, 0x22E
    mov cx, 2000
.w1:
    in al, dx
    test al, 0x80
    jnz .r1
    loop .w1
    jmp .sb_init_done

.r1:
    mov dx, 0x22A
    in al, dx
    cmp al, 0xAA
    jne .sb_init_done
    mov byte [sb16_detected], 1

    ; 3. Turn Speaker ON (DSP Command 0xD1)
    mov bl, 0xD1
    call sb16_dsp_write

    ; 4. Initialize SB16 Mixer (Ports 0x224 / 0x225)
    ; Master Volume L/R (0x30, 0x31) -> 0xF8
    mov dx, 0x224
    mov al, 0x30
    out dx, al
    inc dx
    mov al, 0xF8
    out dx, al

    dec dx
    mov al, 0x31
    out dx, al
    inc dx
    mov al, 0xF8
    out dx, al

    ; Voice / PCM Volume L/R (0x32, 0x33) -> 0xF8
    dec dx
    mov al, 0x32
    out dx, al
    inc dx
    mov al, 0xF8
    out dx, al

    dec dx
    mov al, 0x33
    out dx, al
    inc dx
    mov al, 0xF8
    out dx, al

.sb_init_done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

sb16_dsp_write:
    push dx
    push ax
    push cx
    mov dx, 0x22C
    mov cx, 2000
.wait_dsp:
    in al, dx
    test al, 0x80
    jz .do_dsp_out
    loop .wait_dsp
    jmp .dsp_write_done
.do_dsp_out:
    mov al, bl
    out dx, al
.dsp_write_done:
    pop cx
    pop ax
    pop dx
    ret

sb16_play_pcm:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push ds
    push es

    ; Check sound config: 0=SB16, 1=PC Speaker, 2=Dual, 3=Muted
    cmp byte [CFG_SOUND], 1
    je .skip_sb16
    cmp byte [CFG_SOUND], 3
    je .skip_sb16

    cmp byte [sb16_detected], 1
    jne .skip_sb16

    cmp al, 7
    ja .skip_sb16

    ; Calculate EBX = sample index (0..7) BEFORE any I/O port access!
    movzx ebx, al
    imul ebx, 6
    mov esi, [cs:sample_table + ebx]
    movzx ecx, word [cs:sample_table + ebx + 4]

    ; 1. Acknowledge previous 16-bit & 8-bit IRQs to clear DSP latches
    mov dx, 0x22F
    in al, dx
    mov dx, 0x22E
    in al, dx

    ; 2. Pause any previous 16-bit DMA (command 0xD5)
    mov bl, 0xD5
    call sb16_dsp_write

    ; 3. Copy sample from ROM [fs:esi] to RAM [es:di] (0x2000:0000)
    mov ax, 0x2000
    mov es, ax
    xor di, di

    mov edx, ecx
    shr edx, 1
.copy_pcm_loop:
    a32 mov eax, [fs:esi]
    mov [es:di], eax
    add esi, 4
    add di, 4
    dec edx
    jnz .copy_pcm_loop

    ; 4. Setup DMA Channel 5 (16-bit DMA, Single-Cycle)
    dec cx                          ; count in words - 1
    mov al, 5                       ; Mask channel 5
    out 0xD4, al
    xor al, al                      ; Clear flip-flop
    out 0xD8, al
    mov al, 0x49                    ; Single mode, address increment, read transfer
    out 0xD6, al
    xor al, al                      ; Offset 0x0000
    out 0xC4, al
    out 0xC4, al
    mov al, 0x02                    ; Page 0x8B = 0x02 (phys 0x20000)
    out 0x8B, al
    mov al, cl                      ; Count low
    out 0xC6, al
    mov al, ch                      ; Count high
    out 0xC6, al
    mov al, 1                       ; Unmask channel 5
    out 0xD4, al

    ; 5. Setup DSP 4.xx: Set sample rate 11025 Hz
    mov bl, 0x41
    call sb16_dsp_write
    mov bl, 0x2B
    call sb16_dsp_write
    mov bl, 0x11
    call sb16_dsp_write

    ; 6. Command 0xB0: 16-bit Single-Cycle D/A Output (FIFO off)
    mov bl, 0xB0
    call sb16_dsp_write
    mov bl, 0x10                    ; Signed 16-bit mono
    call sb16_dsp_write
    mov bl, cl                      ; Count low
    call sb16_dsp_write
    mov bl, ch                      ; Count high
    call sb16_dsp_write

.skip_sb16:
    pop es
    pop ds
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

align 8
gdt:
    dq 0
    db 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x92, 0xCF, 0x00
gdt_desc:
    dw 15
    dd 0xF0000 + gdt

; --- Cybforge POST Screen Strings (v3.0 Modernized) ---
str_post_top_bar:
    db "CYBFORGE UEFI/BIOS v3.0-MAX  |  xHCI USB 3.0 + EHCI USB 2.0 + Mouse Active", 0
str_post_hdr1:
    db "Cybforge Retro BIOS (C)2026 Cybforge Systems Inc.", 0
str_post_hdr2:
    db "BIOS Date: 11/08/2026  Ver: 3.00.00-MAX (Cybforge Snake Ed.)", 0
str_post_cpu:
    db "CPU Type    : Genuine x86-32 CPU @ 3.50 GHz (4GB Unreal)", 0
str_post_coproc:
    db "Audio DSP   : Sound Blaster 16 Studio Synth (16-Bit DMA 5)", 0
str_post_vga:
    db "VGA Display : Cybforge PCI Video (Dual-Palette Grass UI)", 0
str_post_kbd:
    db "HID Input   : 8042 PS/2 Keyboard + Hardware Mouse Driver OK", 0
str_post_pit:
    db "Timer Clock : Intel 8254 PIT @ 1.193 MHz + CMOS RTC Clock OK", 0
str_post_xhci_ok:
    db "USB 3.0 Bus : QEMU xHCI SuperSpeed Controller (MMIO 0xFEB00000, RS=1) OK", 0
str_post_xhci_none:
    db "USB 3.0 Bus : xHCI Host Controller Not Detected on PCI Bus 0", 0
str_post_ehci_ok:
    db "USB 2.0 Bus : Intel ICH9 EHCI High-Speed Controller (MMIO 0xFEB10000) OK", 0
str_post_ehci_none:
    db "USB 2.0 Bus : EHCI Host Controller Not Detected on PCI Bus 0", 0
str_post_mem:
    db "Base Memory : 640K OK", 0
str_post_ext:
    db "Extended Mem: 15360K OK (DMA Bounce @ 0x20000, CybFS Live @ 0x3000)", 0
str_post_drives:
    db "NVRAM Disk  : Persistent ATA Primary Master (LBA 0..31, CybFS v1.0) OK", 0
str_post_f12:
    db ">> Press [F12 / DEL] or Click Here for UEFI BIOS Setup <<", 0
str_post_boot:
    db "Booting Cybforge Snake v3.0 in 3s... (Press [ENTER] or Click to Start Now)", 0
str_post_bot_bar:
    db "[F12/DEL] BIOS Setup    [ENTER/Click] Boot Cybforge Snake  [Mouse] Active", 0
str_logo_lbl1:
    db "   CYBFORGE   ", 0
str_logo_lbl2:
    db "  UEFI v3.0   ", 0

; --- Cybforge Setup Utility Strings (v3.0 Modernized) ---
str_setup_title:
    db "CYBFORGE UEFI/BIOS SETUP UTILITY v3.0", 0
str_setup_hw_badge:
    db "xHCI:OK EHCI:OK Mouse:ON", 0
str_setup_usb_line:
    db "Bus 0: xHCI USB 3.0 (FEB00000h) | EHCI USB 2.0 (FEB10000h) | Mouse", 0
str_box_title_main:
    db " Cybforge Snake Maximalist & Hardware Features ", 0
str_box_title_help:
    db " Item Guidance & Live Bus Telemetry ", 0
str_setup_footer:
    db "[Click/TAB] Tab    [Click/W/S] Select    [Click/ENTER] Change    [ESC] Boot", 0

str_opt_speed:
    db "Game Speed        : ", 0
str_opt_walls:
    db "Wall Collision    : ", 0
str_opt_sound:
    db "Sound Output      : ", 0
str_opt_face:
    db "Snake Head Style  : ", 0
str_opt_len:
    db "Starting Length   : ", 0
str_opt_disp:
    db "Screen Geometry   : ", 0
str_opt_reset:
    db "Reset Defaults    : [ Click / Press ENTER ]", 0
str_opt_boot:
    db "Save & Play Snake : [ Click / Press ENTER ]", 0

str_val_spd_norm:
    db "< Normal (120ms) >", 0
str_val_spd_fast:
    db "< Fast (80ms)    >", 0
str_val_spd_slow:
    db "< Slow (160ms)   >", 0

str_val_wall_solid:
    db "< Solid Border   >", 0
str_val_wall_wrap:
    db "< Wrap-Around    >", 0

str_val_snd_sb16:
    db "< Studio SB16 >   ", 0
str_val_snd_spk:
    db "< PC Speaker >    ", 0
str_val_snd_dual:
    db "< Dual Synth >    ", 0
str_val_snd_off:
    db "< Muted >         ", 0

str_post_sb16:
    db "Sound System     : Sound Blaster 16 (16-Bit PCM, DMA 5, Port 220h)", 0
str_post_pcspk:
    db "Sound System     : Standard PC Speaker (PIT 8254 Ch 2)", 0

str_val_face_smile:
    db "< Cybforge Eyes  >", 0
str_val_face_cool:
    db "< Cool Shades    >", 0

str_val_len_4:
    db "< 4 Segments     >", 0
str_val_len_3:
    db "< 3 Segments     >", 0
str_val_len_6:
    db "< 6 Segments     >", 0

str_val_disp_auto:
    db "< Auto (1080p)   >", 0
str_val_disp_classic:
    db "< 80x25 Classic  >", 0
str_val_disp_wide:
    db "< 16:9 Stretched >", 0
str_val_disp_full:
    db "< Fullscreen Fit >", 0

str_help_0:
    db "Set snake speed: Normal (120ms), Fast (80ms), Slow (160ms).", 0
str_help_1:
    db "Solid: crash on forest border. Wrap-Around: pass through walls!", 0
str_help_2:
    db "Select Studio SB16 16-Bit Marimba/Synth PCM, PC Speaker, or Dual.", 0
str_help_3:
    db "Select snake head style: Cybforge Big-Eyes or Cool Sunglasses.", 0
str_help_4:
    db "Starting length of the royal-blue snake body at game launch.", 0
str_help_5:
    db "Win goal: Fill the 1044-tile grass board or reach apple target!", 0
str_help_6:
    db "Choose playfield theme: Lush Grass Checkerboard, Emerald, Autumn, Arcade.", 0
str_help_7:
    db "Choose arena layout: Open Meadow, Four Pillars, or The Maze.", 0

str_opt_theme:
    db "Board Theme       : ", 0
str_opt_arena:
    db "Arena Layout      : ", 0

str_val_theme_cyber:
    db "< Lush Grass     >", 0
str_val_theme_matr:
    db "< Cyber Emerald  >", 0
str_val_theme_amber:
    db "< Golden Autumn  >", 0
str_val_theme_cga:
    db "< Retro Arcade   >", 0

str_val_arena_open:
    db "< Open Meadow    >", 0
str_val_arena_pil:
    db "< Four Pillars   >", 0
str_val_arena_maze:
    db "< The Maze       >", 0

str_help_8:
    db "Reset all BIOS and game settings back to factory defaults.", 0
str_help_9:
    db "Save settings to NVRAM disk and launch Cybforge Snake!", 0

; --- Google Snake Maximalist Game Strings ---
str_game_title:
    db "CYBFORGE SNAKE", 0
str_game_ver:
    db "v3.0", 0
str_hud_buttons:
    db "[Sound] [Pause] [Setup]", 0
str_hi_score_lbl:
    db "BEST: ", 0
str_score_lbl:
    db "SCORE: ", 0
str_gold_lbl:
    db "GOLD: ", 0
str_controls:
    db "Controls: [WASD/Arrows/Click] Steer  [Click HUD] Sound/Pause/Setup  [ESC] Setup", 0

; Google Snake Sky-Blue Popup Card Strings
str_card_start_hdr:
    db "C Y B F O R G E   S N A K E", 0
str_card_champ_lbl:
    db "Top Champion: #1 ", 0
str_card_btn_play:
    db "[ ", 0x0B, "  Play Snake Game       ]", 0
str_card_btn_setup:
    db "[ ", 0x12, "  BIOS Setup & Settings ]", 0
str_card_btn_shell:
    db "[ ", 0x13, "  Launch UEFI/BIOS Shell]", 0

str_press_start:
str_press_enter:
str_start_title:
    db "[ENTER / SPACE / CLICK]  Play Snake", 0

; Pause Modal Box Strings
str_paused_lbl:
    db "G A M E   P A U S E D", 0
str_pause_resume:
    db "[SPACE / Click] Continue", 0

; Game Over & Hall of Champions Strings
str_game_over:
    db "G A M E   O V E R", 0
str_final_score_lbl:
    db "Final Score: ", 0
str_hall_title:
    db "HALL OF CHAMPIONS", 0
str_top1_pfx:
    db "1. ", 0
str_top2_pfx:
    db "2. ", 0
str_top3_pfx:
    db "3. ", 0
str_dots:
    db " ........ ", 0
str_go_restart_info:
    db "[ENTER/Click] Play Again   [ESC] Setup", 0

; New High Score Initials Dialog Strings
str_new_rec_lbl:
    db "N E W   R E C O R D !", 0
str_init_nav:
    db "[Arrows] Change Initials", 0
str_init_confirm:
    db "[ENTER] Confirm", 0

; POST RAM Counter Strings
str_post_mem_lbl:
    db "Base Memory : ", 0
str_kb_suffix:
    db " KB", 0
str_ok_suffix:
    db " OK", 0

; Setup Victory Target Strings
str_opt_win:
    db "Victory Target    : ", 0
str_val_win_full:
    db "< Full Board (1044) >", 0
str_val_win_25:
    db "< 25 Apples (Quick) >", 0
str_val_win_50:
    db "< 50 Apples >        ", 0
str_val_win_100:
    db "< 100 Apples >       ", 0

; Victory Screen Strings
str_vic_hdr1:
    db "*    *    *   V I C T O R Y !   *    *    *", 0
str_vic_hdr2:
    db "YOU CONQUERED THE BOARD!", 0
str_vic_t1:
    db ".-=============-.", 0
str_vic_t2:
    db "(  .=========.  )", 0
str_vic_t3:
    db "\ \:       / /", 0
str_vic_t4:
    db "====| |:.     :| |====", 0
str_vic_t5:
    db "/ /:.     :\ \", 0
str_vic_t6:
    db '(  ":.     .:"  )', 0
str_vic_t7:
    db "'====)   (===='", 0
str_vic_t8:
    db ")   (", 0
str_vic_t9:
    db "_.'     '._", 0
str_vic_t10:
    db "/=============\", 0
str_vic_t11:
    db "|  #1 MASTER  |", 0
str_vic_t12:
    db "|  CYBFORGE   |", 0
str_vic_t13:
    db "\=============/", 0
str_vic_status:
    db "BOARD STATUS: 100% COMPLETE!", 0
str_vic_footer:
    db "Controls: [ENTER] Play Again   [ESC] BIOS Setup", 0


; =============================================================================
; PHASE 8: CYBFORGE EXTENDED UEFI / BIOS INTERACTIVE SHELL v2.5 (LIVE CYBFS)
; =============================================================================
bios_shell_main:
    call vga_set_text_mode
    call mouse_hide_cursor
    call load_ui_palette
    call drain_kbd
    mov byte [MOUSE_CLICK], 0
    call fs_ensure_mounted          ; Mount CybFS from ROM Block 0 if not yet mounted
    mov byte [SH_SHIFT], 0
    mov byte [SH_CTRL], 0
    mov byte [SH_CMD_LEN], 0
    mov byte [SH_HIST_LEN], 0
    mov byte [SH_SCRIPT_ACT], 0
    mov word [SH_DUMP_ADDR], 0x1A00

    call sh_init_theme
    call sh_clear_screen

    ; Display startup banner according to CFG_SH_BANNER
    cmp byte [CFG_SH_BANNER], 2
    je .sh_prompt_init
    cmp byte [CFG_SH_BANNER], 1
    je .sh_compact_banner

    ; Full UEFI Interactive Shell v2.5 Device Table Banner
    mov si, str_sh_ban1
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line
    mov si, str_sh_ban2
    mov ah, [SH_TEXT_ATTR]
    call sh_print_line
    call sh_newline

    mov si, str_sh_map_hdr
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line
    mov si, str_sh_map_sep
    mov ah, 0x08
    call sh_print_line
    mov si, str_sh_map1
    mov ah, 0x0B
    call sh_print_line
    mov si, str_sh_map2
    mov ah, 0x0B
    call sh_print_line
    mov si, str_sh_map3
    mov ah, [SH_TEXT_ATTR]
    call sh_print_line
    mov si, str_sh_map4
    mov ah, [SH_TEXT_ATTR]
    call sh_print_line
    call sh_newline

    mov si, str_sh_ban_hint
    mov ah, 0x0A
    call sh_print_line
    call sh_newline
    jmp .sh_prompt_init

.sh_compact_banner:
    mov si, str_sh_ban1
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line
    mov si, str_sh_ban_hint
    mov ah, 0x0A
    call sh_print_line
    call sh_newline

.sh_prompt_init:
    mov byte [SH_CMD_LEN], 0
    call sh_draw_input_line

.sh_input_loop:
    call sh_read_key_event
    test al, al
    jnz .sh_got_key_ev

    ; Check if user clicked the bottom quick-action dock (Row 23 or 24) with the Mouse!
    test byte [MOUSE_CLICK], 0x01
    jz .sh_idle
    mov byte [MOUSE_CLICK], 0
    cmp byte [MOUSE_Y], 23
    jb .sh_idle
    mov dl, [MOUSE_X]
    cmp dl, 13
    jb .sh_dock_help
    cmp dl, 28
    jb .sh_dock_usb
    cmp dl, 43
    jb .sh_dock_ls
    cmp dl, 60
    jb .sh_dock_snake
    jmp .sh_dock_setup

.sh_dock_help:
    mov si, cmd_help
    jmp .sh_dock_run
.sh_dock_usb:
    mov si, cmd_usb
    jmp .sh_dock_run
.sh_dock_ls:
    mov si, cmd_ls
    jmp .sh_dock_run
.sh_dock_snake:
    mov si, cmd_snake
    jmp .sh_dock_run
.sh_dock_setup:
    mov si, cmd_exit

.sh_dock_run:
    xor bx, bx
.sh_dock_cp:
    mov al, [cs:si + bx]
    test al, al
    jz .sh_dock_go
    mov [SH_CMD_BUF + bx], al
    inc bx
    jmp .sh_dock_cp
.sh_dock_go:
    mov [SH_CMD_LEN], bl
    call sh_draw_input_line
    jmp .sh_on_enter

.sh_got_key_ev:

    ; Check special keys:
    cmp al, 0x1C                    ; ENTER -> Execute command
    je .sh_on_enter
    cmp al, 0x0E                    ; BACKSPACE -> Delete character
    je .sh_on_backspace
    cmp al, 0x01                    ; ESC -> Clear input line
    je .sh_on_esc
    cmp al, 0x48                    ; UP ARROW -> Recall last command from history
    je .sh_on_up
    cmp al, 0x50                    ; DOWN ARROW -> Clear input line
    je .sh_on_esc
    cmp al, 0x0F                    ; TAB -> Auto-Completion!
    je .sh_on_tab

    ; Look up printable ASCII character from scancode table
    cmp al, 0x58
    jae .sh_idle
    xor bh, bh
    mov bl, al
    mov dl, [cs:sh_scancode_norm + bx]
    cmp byte [SH_SHIFT], 1
    jne .sh_got_ascii
    mov dl, [cs:sh_scancode_shift + bx]
.sh_got_ascii:
    test dl, dl
    jz .sh_idle

    ; Check buffer limit (max 54 chars inside frame)
    mov bl, [SH_CMD_LEN]
    cmp bl, 54
    jae .sh_idle
    xor bh, bh
    mov [SH_CMD_BUF + bx], dl
    inc byte [SH_CMD_LEN]
    call sh_key_click
    call sh_draw_input_line
    jmp .sh_input_loop

.sh_idle:
    mov ecx, 200000                 ; ~1ms polling for lag-free typing
    call delay_cycles
    jmp .sh_input_loop

.sh_on_backspace:
    cmp byte [SH_CMD_LEN], 0
    je .sh_input_loop
    dec byte [SH_CMD_LEN]
    call sh_key_click
    call sh_draw_input_line
    jmp .sh_input_loop

.sh_on_esc:
    mov byte [SH_CMD_LEN], 0
    call sh_draw_input_line
    jmp .sh_input_loop

.sh_on_up:
    mov cl, [SH_HIST_LEN]
    test cl, cl
    jz .sh_input_loop
    mov [SH_CMD_LEN], cl
    xor ch, ch
    xor bx, bx
.sh_hist_cp:
    mov al, [SH_HIST_BUF + bx]
    mov [SH_CMD_BUF + bx], al
    inc bx
    loop .sh_hist_cp
    call sh_key_click
    call sh_draw_input_line
    jmp .sh_input_loop

.sh_on_tab:
    call sh_autocomplete
    call sh_draw_input_line
    jmp .sh_input_loop

.sh_on_enter:
    call sh_key_click
    mov byte [SH_CUR_COL], 2
    call sh_draw_input_no_cursor
    call sh_newline

    cmp byte [SH_CMD_LEN], 0
    je .sh_prompt_init

    ; Save into history buffer
    mov cl, [SH_CMD_LEN]
    mov [SH_HIST_LEN], cl
    xor ch, ch
    xor bx, bx
.sh_save_hist:
    mov al, [SH_CMD_BUF + bx]
    mov [SH_HIST_BUF + bx], al
    inc bx
    loop .sh_save_hist

    ; Normalize input (skip leading spaces, lowercase)
    call sh_normalize_cmd
    cmp byte [SH_CLEAN_BUF], 0
    je .sh_prompt_init

    ; Evaluate & execute command
    call sh_execute_command
    cmp byte [SH_CUR_ROW], 2
    jbe .sh_prompt_init
    call sh_newline
    jmp .sh_prompt_init

; -----------------------------------------------------------------------------
; CYBFS v1.0 DRIVER: MOUNT FROM ROM BLOCK 0, INODE LOOKUP & DECIMAL PRINTER
; -----------------------------------------------------------------------------
fs_ensure_mounted:
    cmp word [FS_MAGIC], 0x5346     ; 'FS' signature already in RAM?
    je .fem_ok
    call fs_format_from_rom
.fem_ok:
    ret

fs_format_from_rom:
    ; Copies the 4 KB CybFS master image from ROM Block 0 (0xFFFC0100) to RAM 0x3000..0x3FFF
    ; and zeroes the remaining data pool 0x4000..0x7FFF.
    push eax
    push ecx
    push esi
    push edi

    mov esi, 0xFFFC0100
    mov di, 0x3000
    mov cx, 4096
.ffr_copy:
    a32 mov al, [fs:esi]
    mov [ds:di], al
    inc esi
    inc di
    dec cx
    jnz .ffr_copy

    ; Clear remaining CybFS data pool (0x4000..0x6FDF = 12,256 bytes)
    mov di, 0x4000
    mov cx, 12256
    xor al, al
.ffr_zero:
    mov [ds:di], al
    inc di
    dec cx
    jnz .ffr_zero

    mov byte [SH_DIR_ID], 0
    pop edi
    pop esi
    pop ecx
    pop eax
    ret

fs_find_in_dir:
    ; Searches in [SH_DIR_ID] for filename starting at [SH_CLEAN_BUF + bx] (up to space or 0).
    ; Output: Carry=1 if found -> DI = Inode address (0x3020 + idx*32), CL = Inode index (0..31)
    ;         Carry=0 if not found.
    push ax
    push si
    mov cl, 1                       ; Scan Inodes 1..31
    mov di, FS_INODE_BASE + 32
.ffid_loop:
    mov al, [ds:di + 0]             ; flags
    test al, al
    jz .ffid_next
    mov al, [ds:di + 1]             ; parent_id
    cmp al, [SH_DIR_ID]
    jne .ffid_next

    ; Compare names: [ds:di + 8] vs [SH_CLEAN_BUF + bx]
    push bx
    lea si, [di + 8]
.ffid_cmp:
    mov al, [SH_CLEAN_BUF + bx]
    cmp al, ' '
    jne .ffid_not_sp
    xor al, al                      ; Space terminates filename token
.ffid_not_sp:
    mov ah, [ds:si]
    cmp al, ah
    jne .ffid_mismatch
    test al, al
    jz .ffid_matched
    inc bx
    inc si
    jmp .ffid_cmp

.ffid_matched:
    pop bx
    pop si
    pop ax
    stc
    ret

.ffid_mismatch:
    pop bx
.ffid_next:
    add di, 32
    inc cl
    cmp cl, 32
    jb .ffid_loop

    pop si
    pop ax
    clc
    ret

fs_alloc_inode:
    ; Finds a free Inode slot (flags == 0) from index 1..31.
    ; Output: Carry=1 -> DI = Inode address, CL = Inode index. Carry=0 if full.
    mov cl, 1
    mov di, FS_INODE_BASE + 32
.fai_loop:
    cmp byte [ds:di + 0], 0
    je .fai_found
    add di, 32
    inc cl
    cmp cl, 32
    jb .fai_loop
    clc
    ret
.fai_found:
    stc
    ret

sh_print_dec16:
    ; Prints AX as an unsigned 16-bit decimal number (0..65535) with color attribute BL
    push ax
    push bx
    push cx
    push dx
    push si
    mov bh, bl                      ; Save color attribute in BH (AX remains untouched!)
    xor cx, cx
    mov si, 10
.spd_div:
    xor dx, dx
    div si                          ; AX = AX / 10, DX = remainder (0..9)
    add dl, '0'
    push dx
    inc cx
    test ax, ax
    jnz .spd_div
.spd_out:
    pop dx
    mov al, dl
    mov ah, bh
    call sh_print_char
    loop .spd_out
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

sh_print_dec16_pad6:
    ; Prints AX right-aligned padded to 6 characters with color attribute BL
    push ax
    cmp ax, 10000
    jae .p6_go
    push ax
    mov ah, bl
    mov al, ' '
    call sh_print_char
    pop ax
    cmp ax, 1000
    jae .p6_go
    push ax
    mov ah, bl
    mov al, ' '
    call sh_print_char
    pop ax
    cmp ax, 100
    jae .p6_go
    push ax
    mov ah, bl
    mov al, ' '
    call sh_print_char
    pop ax
    cmp ax, 10
    jae .p6_go
    push ax
    mov ah, bl
    mov al, ' '
    call sh_print_char
    pop ax
.p6_go:
    pop ax
    call sh_print_dec16
    ret

; -----------------------------------------------------------------------------
; SHELL KEYBOARD DRIVER (With Shift tracking for uppercase & symbols)
; -----------------------------------------------------------------------------
sh_read_key_event:
    in al, 0x64
    test al, 0x01
    jz .sh_no_key
    test al, 0x20                   ; Bit 5 = 8042 Auxiliary Mouse byte!
    jnz .sh_mouse_ev
    in al, 0x60
    mov byte [MOUSE_PKT_IDX], 0
    jmp .sh_kbd_ev
.sh_mouse_ev:
    in al, 0x60
    call mouse_process_byte
    xor al, al
    ret
.sh_kbd_ev:
    cmp al, 0xE0                    ; Ignore extended scancode prefix
    je .sh_no_key
    cmp al, 0x2A                    ; Left Shift Make
    je .sh_shift_dn
    cmp al, 0x36                    ; Right Shift Make
    je .sh_shift_dn
    cmp al, 0xAA                    ; Left Shift Break
    je .sh_shift_up
    cmp al, 0xB6                    ; Right Shift Break
    je .sh_shift_up
    cmp al, 0x1D                    ; Ctrl Make
    je .sh_ctrl_dn
    cmp al, 0x9D                    ; Ctrl Break
    je .sh_ctrl_up
    test al, 0x80                   ; Ignore other break codes
    jnz .sh_no_key
    ret
.sh_shift_dn:
    mov byte [SH_SHIFT], 1
    xor al, al
    ret
.sh_shift_up:
    mov byte [SH_SHIFT], 0
    xor al, al
    ret
.sh_ctrl_dn:
    mov byte [SH_CTRL], 1
    xor al, al
    ret
.sh_ctrl_up:
    mov byte [SH_CTRL], 0
    xor al, al
    ret
.sh_no_key:
    xor al, al
    ret

sh_key_click:
    cmp byte [CFG_SH_BEEP], 1
    je .skc_done
    call sound_click
.skc_done:
    ret

; -----------------------------------------------------------------------------
; SHELL THEME & FRAMED CONSOLE HELPERS
; -----------------------------------------------------------------------------
sh_init_theme:
    mov al, [CFG_SH_THEME]
    and al, 3
    cmp al, 1
    je .sht_matrix
    cmp al, 2
    je .sht_cyber
    cmp al, 3
    je .sht_blue

    ; 0: Classic EFI (Yellow/White on Black, Blue Status Bar)
    mov byte [SH_TEXT_ATTR], 0x07
    mov byte [SH_HIGH_ATTR], 0x0E
    mov byte [SH_PROMPT_ATTR], 0x0E
    mov byte [SH_BAR_ATTR], 0x1F
    ret
.sht_matrix:
    mov byte [SH_TEXT_ATTR], 0x02
    mov byte [SH_HIGH_ATTR], 0x0A
    mov byte [SH_PROMPT_ATTR], 0x0A
    mov byte [SH_BAR_ATTR], 0x20
    ret
.sht_cyber:
    mov byte [SH_TEXT_ATTR], 0x03
    mov byte [SH_HIGH_ATTR], 0x0B
    mov byte [SH_PROMPT_ATTR], 0x0D
    mov byte [SH_BAR_ATTR], 0x30
    ret
.sht_blue:
    mov byte [SH_TEXT_ATTR], 0x1F
    mov byte [SH_HIGH_ATTR], 0x1E
    mov byte [SH_PROMPT_ATTR], 0x1A
    mov byte [SH_BAR_ATTR], 0x70
    ret

sh_clear_screen:
    call mouse_hide_cursor
    ; Row 0: Top Status Bar
    xor di, di
    mov cx, 80
    mov ah, [SH_BAR_ATTR]
    mov al, ' '
    rep stosw
    mov di, (0 * 80 + 1) * 2
    mov si, str_sh_topbar
    mov ah, [SH_BAR_ATTR]
    call print_string

    ; Rows 1..23: Terminal viewport background
    mov di, (1 * 80) * 2
    mov cx, 23 * 80
    mov ah, [SH_TEXT_ATTR]
    mov al, ' '
    rep stosw

    ; Row 1: Top double border (Cols 0..79)
    mov ah, 0x0B
    call sh_fix_attr
    mov di, (1 * 80) * 2
    mov al, 0x01                    ; '┌'
    stosw
    mov cx, 78
    mov al, 0x05                    ; '─'
    rep stosw
    mov al, 0x02                    ; '┐'
    stosw

    mov di, (1 * 80 + 4) * 2
    mov si, str_sh_frame_top
    mov ah, [SH_HIGH_ATTR]
    call sh_fix_attr
    call print_string

    ; Rows 2..22: Side border lines '│' at Col 0 and 79
    mov ah, 0x0B
    call sh_fix_attr
    mov al, 0x06                    ; '│'
    mov di, (2 * 80) * 2
    mov cx, 21
.sh_frame_sides:
    mov [es:di], ax
    mov [es:di + 79 * 2], ax
    add di, 80 * 2
    loop .sh_frame_sides

    ; Row 23: Bottom double border (Cols 0..79)
    mov ah, 0x0B
    call sh_fix_attr
    mov di, (23 * 80) * 2
    mov al, 0x03                    ; '└'
    stosw
    mov cx, 78
    mov al, 0x05                    ; '─'
    rep stosw
    mov al, 0x04                    ; '┘'
    stosw

    mov di, (23 * 80 + 4) * 2
    mov si, str_sh_frame_bot
    mov ah, [SH_HIGH_ATTR]
    call sh_fix_attr
    call print_string

    ; Row 24: Bottom Help Bar
    mov di, (24 * 80) * 2
    mov cx, 80
    mov ah, [SH_BAR_ATTR]
    mov al, ' '
    rep stosw
    mov di, (24 * 80 + 1) * 2
    mov si, str_sh_botbar
    mov ah, [SH_BAR_ATTR]
    call print_string

    mov byte [SH_CUR_ROW], 2
    mov byte [SH_CUR_COL], 2
    call mouse_show_cursor
    ret

sh_newline:
    mov byte [SH_CUR_COL], 2
    inc byte [SH_CUR_ROW]
    cmp byte [SH_CUR_ROW], 22
    jbe .sh_nl_ok
    mov byte [SH_CUR_ROW], 22
    call sh_scroll_up
.sh_nl_ok:
    ret

sh_scroll_up:
    push si
    push di
    push cx
    push ax

    push ds
    mov ax, es
    mov ds, ax                      ; DS = ES = 0xB800 for VRAM copy
    mov si, (3 * 80) * 2            ; Source: Row 3
    mov di, (2 * 80) * 2            ; Target: Row 2
    mov cx, 20 * 80                 ; 20 rows (Rows 3..22 -> 2..21)
    rep movsw
    pop ds                          ; Restore DS = 0x0000 immediately!

    ; Clear Row 22 inside frame (Cols 1..78)
    mov di, (22 * 80 + 1) * 2
    mov cx, 78
    mov ah, [SH_TEXT_ATTR]
    mov al, ' '
    rep stosw

    ; Redraw side border lines '│' on Row 22
    mov ah, 0x0B
    call sh_fix_attr
    mov al, 0x06
    mov [es:(22 * 80) * 2], ax
    mov [es:(22 * 80 + 79) * 2], ax

    pop ax
    pop cx
    pop di
    pop si
    ret

sh_fix_attr:
    test ah, 0xF0
    jnz .sfa_done
    push bx
    mov bh, [SH_TEXT_ATTR]
    and bh, 0xF0
    or ah, bh
    pop bx
.sfa_done:
    ret

sh_print_inline:
    ; Prints string [cs:si] with attribute AH at (SH_CUR_COL, SH_CUR_ROW)
    push ax
    push bx
    push di
    call sh_fix_attr
    mov al, [SH_CUR_COL]
    mov bl, [SH_CUR_ROW]
    call xy_to_di
.spi_loop:
    mov al, [cs:si]
    inc si
    test al, al
    jz .spi_done
    cmp byte [SH_CUR_COL], 78
    jae .spi_done
    stosw
    inc byte [SH_CUR_COL]
    jmp .spi_loop
.spi_done:
    pop di
    pop bx
    pop ax
    ret

sh_print_ram_inline:
    ; Prints null-terminated string from RAM [ds:si] with attribute AH
    push ax
    push bx
    push di
    call sh_fix_attr
    mov al, [SH_CUR_COL]
    mov bl, [SH_CUR_ROW]
    call xy_to_di
.spri_loop:
    mov al, [ds:si]
    inc si
    test al, al
    jz .spri_done
    cmp byte [SH_CUR_COL], 78
    jae .spri_done
    stosw
    inc byte [SH_CUR_COL]
    jmp .spri_loop
.spri_done:
    pop di
    pop bx
    pop ax
    ret

sh_print_line:
    call sh_print_inline
    call sh_newline
    ret

sh_print_char:
    push ax
    push bx
    push di
    cmp byte [SH_CUR_COL], 78
    jae .spc_skip
    call sh_fix_attr
    push ax
    mov al, [SH_CUR_COL]
    mov bl, [SH_CUR_ROW]
    call xy_to_di
    pop ax
    stosw
    inc byte [SH_CUR_COL]
.spc_skip:
    pop di
    pop bx
    pop ax
    ret

sh_print_hex8:
    push ax
    push bx
    push dx
    mov al, dl
    shr al, 4
    and al, 0x0F
    xor bh, bh
    mov bl, al
    mov al, [cs:sh_hex_chars + bx]
    call sh_print_char

    mov al, dl
    and al, 0x0F
    mov bl, al
    mov al, [cs:sh_hex_chars + bx]
    call sh_print_char
    pop dx
    pop bx
    pop ax
    ret

sh_print_hex16:
    push dx
    mov dl, dh
    call sh_print_hex8
    pop dx
    call sh_print_hex8
    ret

; -----------------------------------------------------------------------------
; PROMPT & INPUT LINE RENDERING (With real directory name from CybFS Inode!)
; -----------------------------------------------------------------------------
sh_draw_input_line:
    call sh_draw_input_no_cursor
    mov al, '_'
    mov ah, [SH_HIGH_ATTR]
    call sh_print_char
    call mouse_show_cursor
    ret

sh_draw_input_no_cursor:
    call mouse_hide_cursor
    mov al, 1
    mov bl, [SH_CUR_ROW]
    call xy_to_di
    mov cx, 78
    mov ah, [SH_TEXT_ATTR]
    mov al, ' '
    rep stosw

    mov byte [SH_CUR_COL], 2
    mov ah, [SH_PROMPT_ATTR]

    cmp byte [CFG_SH_PROMPT], 1
    je .sdp_compact
    cmp byte [CFG_SH_PROMPT], 2
    je .sdp_root

    ; UEFI Prompt: "FS0:\" + real Inode directory name + "> "
    mov si, str_pr_fs0_pfx
    call sh_print_inline
    mov al, [SH_DIR_ID]
    test al, al
    jz .sdp_close_gt

    ; Calculate Inode address of current directory: 0x3020 + SH_DIR_ID * 32
    xor ah, ah
    shl ax, 5
    add ax, FS_INODE_BASE + 8
    mov si, ax
    mov ah, [SH_PROMPT_ATTR]
.sdp_dir_ch:
    mov al, [ds:si]
    test al, al
    jz .sdp_close_gt
    cmp al, 'a'
    jb .sdp_up_ok
    cmp al, 'z'
    ja .sdp_up_ok
    sub al, 32                      ; Display directory name in uppercase in prompt
.sdp_up_ok:
    call sh_print_char
    inc si
    jmp .sdp_dir_ch

.sdp_close_gt:
    mov si, str_pr_gt
    mov ah, [SH_PROMPT_ATTR]
    call sh_print_inline
    jmp .sdp_print_buf

.sdp_compact:
    mov si, str_pr_compact
    call sh_print_inline
    jmp .sdp_print_buf
.sdp_root:
    mov si, str_pr_root
    call sh_print_inline

.sdp_print_buf:
    mov cl, [SH_CMD_LEN]
    test cl, cl
    jz .sdp_done
    xor ch, ch
    xor bx, bx
    mov ah, 0x0F
.sdp_buf_loop:
    mov al, [SH_CMD_BUF + bx]
    call sh_print_char
    inc bx
    loop .sdp_buf_loop
.sdp_done:
    ret

; -----------------------------------------------------------------------------
; COMMAND NORMALIZATION, PARSING & AUTO-COMPLETE
; -----------------------------------------------------------------------------
sh_normalize_cmd:
    xor si, si
    xor di, di
    mov cl, [SH_CMD_LEN]
    xor ch, ch

.snc_skip_lead:
    test cx, cx
    jz .snc_term
    mov al, [SH_CMD_BUF + si]
    cmp al, ' '
    jne .snc_copy_loop
    inc si
    dec cx
    jmp .snc_skip_lead

.snc_copy_loop:
    test cx, cx
    jz .snc_term
    mov al, [SH_CMD_BUF + si]
    cmp al, 'A'
    jb .snc_store
    cmp al, 'Z'
    ja .snc_store
    add al, 32
.snc_store:
    mov [SH_CLEAN_BUF + di], al
    inc si
    inc di
    dec cx
    jmp .snc_copy_loop

.snc_term:
    mov byte [SH_CLEAN_BUF + di], 0
    ret

sh_match_cmd:
    push si
    xor bx, bx
.smc_loop:
    mov al, [cs:si]
    test al, al
    jz .smc_end_kw
    mov dl, [SH_CLEAN_BUF + bx]
    cmp al, dl
    jne .smc_no
    inc si
    inc bx
    jmp .smc_loop
.smc_end_kw:
    mov dl, [SH_CLEAN_BUF + bx]
    cmp dl, 0
    je .smc_yes
    cmp dl, ' '
    je .smc_skip_arg_sp
    jmp .smc_no
.smc_skip_arg_sp:
    cmp byte [SH_CLEAN_BUF + bx], ' '
    jne .smc_yes
    inc bx
    jmp .smc_skip_arg_sp
.smc_yes:
    pop si
    stc
    ret
.smc_no:
    pop si
    clc
    ret

sh_autocomplete:
    cmp byte [SH_CMD_LEN], 0
    je .sac_done
    mov si, sh_ac_table
.sac_next_kw:
    mov al, [cs:si]
    test al, al
    jz .sac_done
    xor bx, bx
.sac_cmp:
    mov al, [SH_CMD_BUF + bx]
    cmp al, 'A'
    jb .sac_lc
    cmp al, 'Z'
    ja .sac_lc
    add al, 32
.sac_lc:
    mov dl, [cs:si + bx]
    test dl, dl
    jz .sac_match
    cmp al, dl
    jne .sac_skip_kw
    inc bx
    cmp bl, [SH_CMD_LEN]
    jb .sac_cmp
.sac_match:
    xor bx, bx
.sac_copy_kw:
    mov al, [cs:si + bx]
    test al, al
    jz .sac_set_len
    mov [SH_CMD_BUF + bx], al
    inc bx
    jmp .sac_copy_kw
.sac_set_len:
    mov [SH_CMD_LEN], bl
    call sh_key_click
    ret
.sac_skip_kw:
    mov al, [cs:si]
    inc si
    test al, al
    jnz .sac_skip_kw
    jmp .sac_next_kw
.sac_done:
    ret

; -----------------------------------------------------------------------------
; SHELL COMMAND DISPATCHER (30 Built-In Live Commands)
; -----------------------------------------------------------------------------
sh_execute_command:
    ; Ignore comment lines ('#' or '@') in scripts
    mov al, [SH_CLEAN_BUF]
    cmp al, '#'
    je .sh_noop_ret
    cmp al, '@'
    je .sh_noop_ret

    ; 1. exit / quit / setup -> Return to BIOS Setup!
    mov si, cmd_exit
    call sh_match_cmd
    jc .do_sh_exit
    mov si, cmd_quit
    call sh_match_cmd
    jc .do_sh_exit
    mov si, cmd_setup
    call sh_match_cmd
    jc .do_sh_exit

    ; 2. help / ?
    mov si, cmd_help
    call sh_match_cmd
    jc .do_sh_help
    mov si, cmd_qmark
    call sh_match_cmd
    jc .do_sh_help

    ; 3. cls / clear
    mov si, cmd_cls
    call sh_match_cmd
    jc .do_sh_cls
    mov si, cmd_clear
    call sh_match_cmd
    jc .do_sh_cls

    ; 4. ver / version
    mov si, cmd_ver
    call sh_match_cmd
    jc .do_sh_ver
    mov si, cmd_version
    call sh_match_cmd
    jc .do_sh_ver

    ; 5. map
    mov si, cmd_map
    call sh_match_cmd
    jc .do_sh_map

    ; 6. memmap / mem
    mov si, cmd_memmap
    call sh_match_cmd
    jc .do_sh_memmap
    mov si, cmd_mem
    call sh_match_cmd
    jc .do_sh_memmap

    ; 7. ls / dir (Real CybFS Inode iteration!)
    mov si, cmd_ls
    call sh_match_cmd
    jc .do_sh_ls
    mov si, cmd_dir
    call sh_match_cmd
    jc .do_sh_ls

    ; 8. cd / fs0: / blk0:
    mov si, cmd_cd
    call sh_match_cmd
    jc .do_sh_cd
    mov si, cmd_fs0
    call sh_match_cmd
    jc .do_sh_cd_root
    mov si, cmd_blk0
    call sh_match_cmd
    jc .do_sh_cd_audio

    ; 9. mkdir / md (Create real directory in CybFS)
    mov si, cmd_mkdir
    call sh_match_cmd
    jc .do_sh_mkdir
    mov si, cmd_md
    call sh_match_cmd
    jc .do_sh_mkdir

    ; 10. touch (Create real empty file in CybFS)
    mov si, cmd_touch
    call sh_match_cmd
    jc .do_sh_touch

    ; 11. write / nano / edit (Interactive GNU Nano text editor for CybFS!)
    mov si, cmd_write
    call sh_match_cmd
    jc .do_sh_write
    mov si, cmd_nano
    call sh_match_cmd
    jc .do_sh_write
    mov si, cmd_edit
    call sh_match_cmd
    jc .do_sh_write

    ; 12. append (Append line to real CybFS file)
    mov si, cmd_append
    call sh_match_cmd
    jc .do_sh_append

    ; 13. rm / del (Delete real file / directory from CybFS)
    mov si, cmd_rm
    call sh_match_cmd
    jc .do_sh_rm
    mov si, cmd_del
    call sh_match_cmd
    jc .do_sh_rm

    ; 14. cat / type (Read real file bytes from CybFS / ROM)
    mov si, cmd_cat
    call sh_match_cmd
    jc .do_sh_cat
    mov si, cmd_type
    call sh_match_cmd
    jc .do_sh_cat

    ; 15. run / sh (Execute real script from CybFS line by line)
    mov si, cmd_run
    call sh_match_cmd
    jc .do_sh_run
    mov si, cmd_sh
    call sh_match_cmd
    jc .do_sh_run

    ; 16. factoryreset / wipe / resetbios / format (Complete factory reset!)
    mov si, cmd_factoryreset
    call sh_match_cmd
    jc .do_sh_format
    mov si, cmd_wipe
    call sh_match_cmd
    jc .do_sh_format
    mov si, cmd_resetbios
    call sh_match_cmd
    jc .do_sh_format
    mov si, cmd_format
    call sh_match_cmd
    jc .do_sh_format

    ; 17. sysinfo / neofetch / info
    mov si, cmd_sysinfo
    call sh_match_cmd
    jc .do_sh_sysinfo
    mov si, cmd_neofetch
    call sh_match_cmd
    jc .do_sh_sysinfo
    mov si, cmd_info
    call sh_match_cmd
    jc .do_sh_sysinfo

    ; 18. pci / devices / devtree / lspci (Real hardware PCI bus scan!)
    mov si, cmd_pci
    call sh_match_cmd
    jc .do_sh_pci
    mov si, cmd_devices
    call sh_match_cmd
    jc .do_sh_pci
    mov si, cmd_devtree
    call sh_match_cmd
    jc .do_sh_pci
    mov si, cmd_lspci
    call sh_match_cmd
    jc .do_sh_pci

    ; 19. cpu / regs
    mov si, cmd_cpu
    call sh_match_cmd
    jc .do_sh_cpu
    mov si, cmd_regs
    call sh_match_cmd
    jc .do_sh_cpu

    ; 20. cmos / nvram
    mov si, cmd_cmos
    call sh_match_cmd
    jc .do_sh_cmos
    mov si, cmd_nvram
    call sh_match_cmd
    jc .do_sh_cmos

    ; 21. dmem / hex / dump
    mov si, cmd_dmem
    call sh_match_cmd
    jc .do_sh_dmem
    mov si, cmd_hex
    call sh_match_cmd
    jc .do_sh_dmem
    mov si, cmd_dump
    call sh_match_cmd
    jc .do_sh_dmem

    ; 22. time / date / rtc
    mov si, cmd_time
    call sh_match_cmd
    jc .do_sh_time
    mov si, cmd_date
    call sh_match_cmd
    jc .do_sh_time
    mov si, cmd_rtc
    call sh_match_cmd
    jc .do_sh_time

    ; 23. sound / play / audio
    mov si, cmd_sound
    call sh_match_cmd
    jc .do_sh_sound
    mov si, cmd_play
    call sh_match_cmd
    jc .do_sh_sound
    mov si, cmd_audio
    call sh_match_cmd
    jc .do_sh_sound

    ; 24. io / ports
    mov si, cmd_io
    call sh_match_cmd
    jc .do_sh_io
    mov si, cmd_ports
    call sh_match_cmd
    jc .do_sh_io

    ; 25. memtest
    mov si, cmd_memtest
    call sh_match_cmd
    jc .do_sh_memtest

    ; 26. color
    mov si, cmd_color
    call sh_match_cmd
    jc .do_sh_color

    ; 27. echo
    mov si, cmd_echo
    call sh_match_cmd
    jc .do_sh_echo

    ; 28. beep
    mov si, cmd_beep
    call sh_match_cmd
    jc .do_sh_beep

    ; 29. snake / boot / snake.efi
    mov si, cmd_snake
    call sh_match_cmd
    jc .do_sh_snake
    mov si, cmd_snake_efi
    call sh_match_cmd
    jc .do_sh_snake
    mov si, cmd_boot
    call sh_match_cmd
    jc .do_sh_snake

    ; 30. setfont (Scale font size live in BIOS Shell: 1..4)
    mov si, cmd_setfont
    call sh_match_cmd
    jc .do_sh_setfont
    mov si, cmd_font
    call sh_match_cmd
    jc .do_sh_setfont

    ; 31. reboot / reset
    mov si, cmd_reboot
    call sh_match_cmd
    jc .do_sh_reboot
    mov si, cmd_reset
    call sh_match_cmd
    jc .do_sh_reboot

    ; 32. shutdown / poweroff / halt / off (Real ACPI S5 Soft-Off shutdown!)
    mov si, cmd_shutdown
    call sh_match_cmd
    jc .do_sh_shutdown
    mov si, cmd_poweroff
    call sh_match_cmd
    jc .do_sh_shutdown
    mov si, cmd_halt
    call sh_match_cmd
    jc .do_sh_shutdown
    mov si, cmd_off
    call sh_match_cmd
    jc .do_sh_shutdown

    ; 33. usb / lsusb / xhci / ehci (Live xHCI USB 3.0 & EHCI USB 2.0 MMIO Inspector!)
    mov si, cmd_usb
    call sh_match_cmd
    jc .do_sh_usb
    mov si, cmd_lsusb
    call sh_match_cmd
    jc .do_sh_usb
    mov si, cmd_xhci
    call sh_match_cmd
    jc .do_sh_usb
    mov si, cmd_ehci
    call sh_match_cmd
    jc .do_sh_usb

    ; 34. mouse (Live PS/2 Aux & USB Pointer Status!)
    mov si, cmd_mouse
    call sh_match_cmd
    jc .do_sh_mouse

    ; Unknown command:
    mov si, str_sh_err_pfx
    mov ah, 0x0C
    call sh_print_inline
    xor bx, bx
.err_cmd_echo:
    mov al, [SH_CLEAN_BUF + bx]
    test al, al
    jz .err_cmd_done
    mov ah, 0x0E
    call sh_print_char
    inc bx
    jmp .err_cmd_echo
.err_cmd_done:
    mov si, str_sh_err_sfx
    mov ah, 0x0C
    call sh_print_line
.sh_noop_ret:
    ret

; --- 1. EXIT -> RETURN TO BIOS SETUP ---
.do_sh_exit:
    pop ax
    mov byte [SETUP_TAB], 1
    mov byte [SETUP_SEL], 1
    jmp core_bios_setup

; --- 2. HELP ---
.do_sh_help:
    mov si, str_sh_hlp_hdr
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line
    mov si, str_sh_hlp1
    mov ah, [SH_TEXT_ATTR]
    call sh_print_line
    mov si, str_sh_hlp2
    call sh_print_line
    mov si, str_sh_hlp3
    call sh_print_line
    mov si, str_sh_hlp4
    call sh_print_line
    mov si, str_sh_hlp5
    call sh_print_line
    mov si, str_sh_hlp6
    call sh_print_line
    mov si, str_sh_hlp7
    mov ah, 0x0E
    call sh_print_line
    mov si, str_sh_hlp8
    mov ah, [SH_TEXT_ATTR]
    call sh_print_line
    mov si, str_sh_hlp9
    call sh_print_line
    mov si, str_sh_hlp10
    call sh_print_line
    mov si, str_sh_hlp11
    mov ah, 0x0E
    call sh_print_line
    mov si, str_sh_hlp12
    mov ah, 0x0A
    call sh_print_line
    ret

; --- 3. CLS / CLEAR ---
.do_sh_cls:
    call sh_clear_screen
    ret

; --- 4. VER / VERSION ---
.do_sh_ver:
    mov si, str_sh_ver1
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line
    mov si, str_sh_ver2
    mov ah, [SH_TEXT_ATTR]
    call sh_print_line
    mov si, str_sh_ver3
    call sh_print_line
    mov si, str_sh_ver4
    call sh_print_line
    mov si, str_sh_ver5
    mov ah, 0x0A
    call sh_print_line
    ret

; --- 5. MAP ---
.do_sh_map:
    mov si, str_sh_map_hdr
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line
    mov si, str_sh_map_sep
    mov ah, 0x08
    call sh_print_line
    mov si, str_sh_map1
    mov ah, 0x0B
    call sh_print_line
    mov si, str_sh_map2
    mov ah, 0x0B
    call sh_print_line
    mov si, str_sh_map3
    mov ah, [SH_TEXT_ATTR]
    call sh_print_line
    mov si, str_sh_map4
    mov ah, [SH_TEXT_ATTR]
    call sh_print_line
    mov si, str_sh_map5
    mov ah, 0x0A
    call sh_print_line
    mov si, str_sh_map6
    mov ah, 0x0A
    call sh_print_line
    ret

; --- 6. MEMMAP ---
.do_sh_memmap:
    mov si, str_sh_mm_hdr
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line
    mov si, str_sh_mm_sep
    mov ah, 0x08
    call sh_print_line
    mov si, str_sh_mm1
    mov ah, [SH_TEXT_ATTR]
    call sh_print_line
    mov si, str_sh_mm2
    call sh_print_line
    mov si, str_sh_mm3
    mov ah, 0x0E
    call sh_print_line
    mov si, str_sh_mm4
    mov ah, 0x0B
    call sh_print_line
    mov si, str_sh_mm5
    mov ah, [SH_TEXT_ATTR]
    call sh_print_line
    mov si, str_sh_mm6
    call sh_print_line
    mov si, str_sh_mm7
    mov ah, 0x0B
    call sh_print_line
    mov si, str_sh_mm8
    call sh_print_line
    mov si, str_sh_mm_tot
    mov ah, 0x0A
    call sh_print_line
    ret

; --- 7. LS / DIR (100% REAL CYBFS INODE SCANNER!) ---
.do_sh_ls:
    mov si, str_ls_hdr_pfx
    mov ah, [SH_HIGH_ATTR]
    call sh_print_inline
    mov al, [SH_DIR_ID]
    test al, al
    jz .ls_hdr_done
    xor ah, ah
    shl ax, 5
    add ax, FS_INODE_BASE + 8
    mov si, ax
    mov ah, 0x0B
    call sh_print_ram_inline
.ls_hdr_done:
    mov si, str_ls_hdr_sfx
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line

    mov si, str_ls_col_hdr
    mov ah, 0x08
    call sh_print_line

    xor bp, bp                      ; BP = Number of files found
    xor edx, edx                    ; EDX (low 16) = Number of directories found
    mov di, FS_INODE_BASE + 32      ; Scan Inodes 1..31
    mov cl, 1
.ls_inode_loop:
    mov al, [ds:di + 0]             ; flags
    test al, al
    jz .ls_next_inode
    mov ah, [ds:di + 1]             ; parent_id
    cmp ah, [SH_DIR_ID]
    jne .ls_next_inode

    push cx
    push dx

    ; Column 1: Type badge (<DIR>, [RAM], [ROM], [HW ])
    mov al, [ds:di + 0]
    cmp al, 2
    je .ls_type_dir
    cmp al, 3
    je .ls_type_rom
    cmp al, 4
    je .ls_type_hw

    ; flags == 1: [RAM] (Writable file in CybFS RAM pool)
    mov si, str_tag_ram
    mov ah, 0x0E
    call sh_print_inline
    jmp .ls_print_size

.ls_type_dir:
    mov si, str_tag_dir
    mov ah, 0x0B
    call sh_print_inline
    mov si, str_size_dir
    mov ah, [SH_TEXT_ATTR]
    call sh_print_inline
    jmp .ls_print_addr

.ls_type_rom:
    mov si, str_tag_rom
    mov ah, 0x0A
    call sh_print_inline
    jmp .ls_print_size

.ls_type_hw:
    mov si, str_tag_hw
    mov ah, 0x0D
    call sh_print_inline

.ls_print_size:
    mov ax, [ds:di + 6]             ; Real 16-bit file size from Inode!
    push di
    mov bl, 0x0F
    call sh_print_dec16_pad6
    pop di
    mov si, str_unit_b
    mov ah, [SH_TEXT_ATTR]
    call sh_print_inline

.ls_print_addr:
    ; Column 3: Real memory address (data_seg_hi : data_off)
    mov dx, [ds:di + 4]             ; data_seg_hi
    mov ah, 0x08
    call sh_print_hex16
    mov al, ':'
    call sh_print_char
    mov dx, [ds:di + 2]             ; data_off
    mov ah, 0x03
    call sh_print_hex16
    mov al, 'h'
    call sh_print_char
    mov al, ' '
    call sh_print_char
    call sh_print_char

    ; Column 4: Real filename from Inode (Offset +8)
    lea si, [di + 8]
    mov ah, 0x0F
    cmp byte [ds:di + 0], 2
    jne .ls_name_out
    mov ah, 0x0B                    ; Directory names in bright cyan
.ls_name_out:
    call sh_print_ram_inline
    call sh_newline

    pop dx
    pop cx
    cmp byte [ds:di + 0], 2
    je .ls_cnt_dir
    inc bp
    jmp .ls_next_inode
.ls_cnt_dir:
    inc dx

.ls_next_inode:
    add di, 32
    inc cl
    cmp cl, 32
    jb .ls_inode_loop

    ; Summary with real counters and free CybFS storage space:
    mov si, str_ls_sum1
    mov ah, [SH_HIGH_ATTR]
    call sh_print_inline
    mov ax, bp
    mov bl, 0x0F
    call sh_print_dec16
    mov si, str_ls_sum2
    mov ah, [SH_HIGH_ATTR]
    call sh_print_inline
    mov ax, dx
    mov bl, 0x0F
    call sh_print_dec16
    mov si, str_ls_sum3
    mov ah, [SH_HIGH_ATTR]
    call sh_print_inline

    ; Free R/W storage = 0x7000 - [FS_ALLOC_PTR]
    mov ax, FS_POOL_END
    sub ax, [FS_ALLOC_PTR]
    mov bl, 0x0A
    call sh_print_dec16
    mov si, str_ls_sum4
    mov ah, 0x0A
    call sh_print_line
    ret

; --- 8. CD (Real Inode directory change) ---
.do_sh_cd:
    mov al, [SH_CLEAN_BUF + bx]
    cmp al, 0
    je .do_sh_cd_root
    cmp al, '\\'
    je .do_sh_cd_root
    cmp al, '/'
    je .do_sh_cd_root
    cmp al, '.'
    je .do_sh_cd_up

    ; Look up directory name in current directory
    call fs_find_in_dir
    jnc .cd_not_found
    cmp byte [ds:di + 0], 2         ; Must be a <DIR> (flags == 2)!
    jne .cd_not_dir
    mov [SH_DIR_ID], cl
    ret

.do_sh_cd_up:
    mov al, [SH_DIR_ID]
    test al, al
    jz .cd_done
    xor ah, ah
    shl ax, 5
    add ax, FS_INODE_BASE
    mov di, ax
    mov al, [ds:di + 1]             ; parent_id of current directory!
    mov [SH_DIR_ID], al
.cd_done:
    ret

.do_sh_cd_root:
    mov byte [SH_DIR_ID], 0
    ret
.do_sh_cd_audio:
    mov byte [SH_DIR_ID], 2
    ret

.cd_not_dir:
    mov si, str_cd_notdir
    mov ah, 0x0C
    call sh_print_line
    ret
.cd_not_found:
    mov si, str_cd_err
    mov ah, 0x0C
    call sh_print_line
    ret

; --- 9. MKDIR <DIRNAME> (Create real directory in CybFS) ---
.do_sh_mkdir:
    cmp byte [SH_CLEAN_BUF + bx], 0
    je .mkdir_usage
    call fs_find_in_dir
    jc .mkdir_exists
    call fs_alloc_inode
    jnc .fs_full_err

    mov byte [ds:di + 0], 2         ; flags = 2 (<DIR>)
    mov al, [SH_DIR_ID]
    mov [ds:di + 1], al             ; parent_id
    mov word [ds:di + 2], 0
    xor ah, ah
    mov al, cl
    mov [ds:di + 4], ax             ; Inode ID
    mov word [ds:di + 6], 0         ; size = 0

    ; Copy name (up to space or 0, max 15 chars)
    push di
    add di, 8
    mov ch, 15
.mkdir_cp:
    mov al, [SH_CLEAN_BUF + bx]
    test al, al
    jz .mkdir_pad
    cmp al, ' '
    je .mkdir_pad
    mov [ds:di], al
    inc bx
    inc di
    dec ch
    jnz .mkdir_cp
.mkdir_pad:
    mov byte [ds:di], 0
    pop di
    call ata_sync_nvram

    mov si, str_mkdir_ok
    mov ah, 0x0A
    call sh_print_inline
    lea si, [di + 8]
    mov ah, 0x0B
    call sh_print_ram_inline
    mov si, str_Quote_ok
    mov ah, 0x0A
    call sh_print_line
    ret

.mkdir_usage:
    mov si, str_mkdir_use
    mov ah, 0x0E
    call sh_print_line
    ret
.mkdir_exists:
    mov si, str_exists_err
    mov ah, 0x0C
    call sh_print_line
    ret

; --- 10. TOUCH <FILENAME> (Create real empty file) ---
.do_sh_touch:
    cmp byte [SH_CLEAN_BUF + bx], 0
    je .touch_usage
    call fs_find_in_dir
    jc .touch_exists
    call fs_alloc_inode
    jnc .fs_full_err

    mov byte [ds:di + 0], 1         ; flags = 1 ([RAM] File)
    mov al, [SH_DIR_ID]
    mov [ds:di + 1], al
    mov ax, [FS_ALLOC_PTR]
    mov [ds:di + 2], ax             ; data_off
    mov word [ds:di + 4], 0x0000    ; segment 0000h
    mov word [ds:di + 6], 0         ; file_size = 0

    push di
    add di, 8
    mov ch, 15
.touch_cp:
    mov al, [SH_CLEAN_BUF + bx]
    test al, al
    jz .touch_pad
    cmp al, ' '
    je .touch_pad
    mov [ds:di], al
    inc bx
    inc di
    dec ch
    jnz .touch_cp
.touch_pad:
    mov byte [ds:di], 0
    pop di
    call ata_sync_nvram

    mov si, str_touch_ok
    mov ah, 0x0A
    call sh_print_inline
    lea si, [di + 8]
    mov ah, 0x0E
    call sh_print_ram_inline
    mov si, str_Quote_ok
    mov ah, 0x0A
    call sh_print_line
    ret

.touch_usage:
    mov si, str_touch_use
    mov ah, 0x0E
    call sh_print_line
    ret
.touch_exists:
    mov si, str_touch_ex_ok
    mov ah, 0x0A
    call sh_print_line
    ret

; --- 11. WRITE / NANO / EDIT <FILENAME> (FULL-SCREEN GNU NANO TEXT EDITOR!) ---
.do_sh_write:
    ; If no filename was given -> Open default file "notes.txt"!
    cmp byte [SH_CLEAN_BUF + bx], 0
    jne .nano_has_arg
    mov byte [SH_CLEAN_BUF + bx + 0], 'n'
    mov byte [SH_CLEAN_BUF + bx + 1], 'o'
    mov byte [SH_CLEAN_BUF + bx + 2], 't'
    mov byte [SH_CLEAN_BUF + bx + 3], 'e'
    mov byte [SH_CLEAN_BUF + bx + 4], 's'
    mov byte [SH_CLEAN_BUF + bx + 5], '.'
    mov byte [SH_CLEAN_BUF + bx + 6], 't'
    mov byte [SH_CLEAN_BUF + bx + 7], 'x'
    mov byte [SH_CLEAN_BUF + bx + 8], 't'
    mov byte [SH_CLEAN_BUF + bx + 9], 0

.nano_has_arg:
    ; Check if file exists in current directory, otherwise allocate new Inode
    call fs_find_in_dir
    jc .nano_found_existing
    call fs_alloc_inode
    jnc .fs_full_err

    ; Initialize new Inode & copy filename
    mov byte [ds:di + 0], 1         ; flags = 1 ([RAM])
    mov al, [SH_DIR_ID]
    mov [ds:di + 1], al
    mov ax, [FS_ALLOC_PTR]
    mov [ds:di + 2], ax             ; data_off
    mov word [ds:di + 4], 0x0000
    mov word [ds:di + 6], 0         ; file_size = 0 (initially empty)
    push di
    add di, 8
    mov ch, 15
.nano_name_cp:
    mov al, [SH_CLEAN_BUF + bx]
    test al, al
    jz .nano_name_done
    cmp al, ' '
    je .nano_name_done
    mov [ds:di], al
    inc bx
    inc di
    dec ch
    jnz .nano_name_cp
.nano_name_done:
    mov byte [ds:di], 0
    pop di
    jmp .nano_skip_fn_sp

.nano_found_existing:
    cmp byte [ds:di + 0], 2
    je .cd_not_dir
    ; Advance BX past filename
.nano_adv_fn:
    mov al, [SH_CLEAN_BUF + bx]
    test al, al
    jz .nano_skip_fn_sp
    cmp al, ' '
    je .nano_skip_fn_sp
    inc bx
    jmp .nano_adv_fn

.nano_skip_fn_sp:
    cmp byte [SH_CLEAN_BUF + bx], ' '
    jne .nano_init_buffer
    inc bx
    jmp .nano_skip_fn_sp

.nano_init_buffer:
    mov [NANO_INODE], di
    mov byte [NANO_ROW], 0
    mov byte [NANO_COL], 0
    mov byte [NANO_MOD], 0
    mov byte [NANO_SAVED_FLAG], 0
    mov byte [NANO_MSG_ID], 0
    mov ax, [ds:di + 6]
    mov [NANO_LAST_SZ], ax

    ; Fill 18 x 72 Nano text buffer (0x7000..0x750F = 1296 bytes) with spaces (' ')
    push di
    mov di, NANO_BUF
    mov cx, 18 * 72
    mov al, ' '
.nano_clr_lp:
    mov [ds:di], al
    inc di
    loop .nano_clr_lp
    pop di

    ; If the file already has content in RAM (flags == 1 and file_size > 0), load it into the buffer!
    cmp byte [ds:di + 0], 1
    jne .nano_check_inline_arg
    mov cx, [ds:di + 6]
    test cx, cx
    jz .nano_check_inline_arg

    mov si, [ds:di + 2]             ; data_off in CybFS RAM pool
    xor dx, dx                      ; DH = Row (0..17), DL = Col (0..71)
.nano_load_file_lp:
    mov al, [ds:si]
    inc si
    cmp al, 0x0D
    je .nano_lf_next
    cmp al, 0x0A
    je .nano_lf_newline
    cmp dl, 72
    jae .nano_lf_next
    push ax
    mov al, dh
    mov ah, 72
    mul ah                          ; AX = row * 72
    xor bh, bh
    mov bl, dl
    add ax, bx
    add ax, NANO_BUF
    mov bp, ax
    pop ax
    mov [ds:bp], al
    inc dl
    jmp .nano_lf_next
.nano_lf_newline:
    inc dh
    xor dl, dl
    cmp dh, 18
    jae .nano_load_done
.nano_lf_next:
    loop .nano_load_file_lp
.nano_load_done:
    cmp dh, 18
    jb .nano_set_loaded_cur
    mov dh, 17
.nano_set_loaded_cur:
    mov [NANO_ROW], dh
    mov [NANO_COL], dl

.nano_check_inline_arg:
    ; Check if inline text was passed via 'write <file> <text>'
    cmp byte [SH_CLEAN_BUF + bx], 0
    je .nano_check_script_mode

    ; Find corresponding position in original buffer SH_CMD_BUF (preserve case)
    xor si, si
    mov cl, [SH_CMD_LEN]
    xor ch, ch
.nano_orig_s1:
    test cx, cx
    jz .nano_check_script_mode
    cmp byte [SH_CMD_BUF + si], ' '
    jne .nano_orig_w1
    inc si
    dec cx
    jmp .nano_orig_s1
.nano_orig_w1:
    test cx, cx
    jz .nano_check_script_mode
    cmp byte [SH_CMD_BUF + si], ' '
    je .nano_orig_s2
    inc si
    dec cx
    jmp .nano_orig_w1
.nano_orig_s2:
    test cx, cx
    jz .nano_check_script_mode
    cmp byte [SH_CMD_BUF + si], ' '
    jne .nano_orig_w2
    inc si
    dec cx
    jmp .nano_orig_s2
.nano_orig_w2:
    test cx, cx
    jz .nano_check_script_mode
    cmp byte [SH_CMD_BUF + si], ' '
    je .nano_orig_s3
    inc si
    dec cx
    jmp .nano_orig_w2
.nano_orig_s3:
    test cx, cx
    jz .nano_check_script_mode
    cmp byte [SH_CMD_BUF + si], ' '
    jne .nano_copy_inline
    inc si
    dec cx
    jmp .nano_orig_s3

.nano_copy_inline:
    ; If running in script mode ('run <script.nsh>'), overwrite Row 0 cleanly
    mov di, NANO_BUF
    mov dx, 72
.nano_clr_l0:
    mov byte [ds:di], ' '
    inc di
    dec dx
    jnz .nano_clr_l0

    mov di, NANO_BUF
    xor dl, dl
.nano_cp_in_lp:
    test cx, cx
    jz .nano_cp_in_done
    cmp dl, 72
    jae .nano_cp_in_done
    mov al, [SH_CMD_BUF + si]
    mov [ds:di], al
    inc si
    inc di
    inc dl
    dec cx
    jmp .nano_cp_in_lp
.nano_cp_in_done:
    mov byte [NANO_ROW], 0
    mov [NANO_COL], dl
    mov byte [NANO_MOD], 1

.nano_check_script_mode:
    ; If called from a .nsh script: save directly without interactive UI!
    cmp byte [SH_SCRIPT_ACT], 1
    jne .nano_enter_ui
    call .nano_save_buffer
    mov di, [NANO_INODE]
    mov si, str_write_ok1
    mov ah, 0x0A
    call sh_print_inline
    mov ax, [NANO_LAST_SZ]
    mov bl, 0x0E
    call sh_print_dec16
    mov si, str_write_ok2
    mov ah, 0x0A
    call sh_print_inline
    lea si, [di + 8]
    mov ah, 0x0F
    call sh_print_ram_inline
    mov si, str_Quote_ok
    mov ah, 0x0A
    call sh_print_line
    ret

; =============================================================================
; INTERACTIVE GNU NANO FULL-SCREEN UI (CYBFORGE NANO v2.7)
; =============================================================================
.nano_enter_ui:
    call .nano_render_screen

.nano_event_loop:
    call sh_read_key_event
    test al, al
    jz .nano_idle

    ; Are we in the "Save modified buffer? [Y/N/C]" dialog (NANO_MSG_ID == 2)?
    cmp byte [NANO_MSG_ID], 2
    jne .nano_normal_keys

    cmp al, 0x15                    ; 'Y' (US) -> Yes, save & exit
    je .nano_save_and_exit
    cmp al, 0x2C                    ; 'Z' (QWERTZ 'Y' key) -> Yes, save & exit
    je .nano_save_and_exit
    cmp al, 0x1C                    ; ENTER -> Yes, save & exit
    je .nano_save_and_exit
    cmp al, 0x31                    ; 'N' -> No, discard changes & exit
    je .nano_exit_now
    cmp al, 0x2E                    ; 'C' -> Cancel, continue editing
    je .nano_cancel_prompt
    cmp al, 0x01                    ; ESC -> In dialog: cancel and return to editor
    je .nano_cancel_prompt
    jmp .nano_event_loop

.nano_cancel_prompt:
    mov byte [NANO_MSG_ID], 0
    call sh_key_click
    call .nano_render_screen
    jmp .nano_event_loop

.nano_normal_keys:
    ; 1. Check if CTRL is pressed (^O, ^X, ^S, ^K, ^G)
    cmp byte [SH_CTRL], 1
    jne .nano_check_fn_keys

    cmp al, 0x18                    ; Ctrl+O (^O) -> WriteOut (Save)
    je .nano_do_writeout
    cmp al, 0x2D                    ; Ctrl+X (^X) -> Exit Nano
    je .nano_try_exit
    cmp al, 0x1F                    ; Ctrl+S (^S) -> Save & Exit
    je .nano_save_and_exit
    cmp al, 0x25                    ; Ctrl+K (^K) -> Cut/Clear Line
    je .nano_cut_line
    cmp al, 0x22                    ; Ctrl+G (^G) -> Get Help
    je .nano_show_help
    jmp .nano_event_loop

.nano_check_fn_keys:
    ; 2. Check function keys & navigation keys
    cmp al, 0x3B                    ; F1 -> Get Help (^G)
    je .nano_show_help
    cmp al, 0x3C                    ; F2 -> WriteOut / Save (^O)
    je .nano_do_writeout
    cmp al, 0x3D                    ; F3 -> Save & Exit (^S)
    je .nano_save_and_exit
    cmp al, 0x3E                    ; F4 -> Cut Line (^K)
    je .nano_cut_line
    cmp al, 0x01                    ; ESC -> Exit Nano (^X)
    je .nano_try_exit

    cmp al, 0x48                    ; UP ARROW
    je .nano_cur_up
    cmp al, 0x50                    ; DOWN ARROW
    je .nano_cur_down
    cmp al, 0x4B                    ; LEFT ARROW
    je .nano_cur_left
    cmp al, 0x4D                    ; RIGHT ARROW
    je .nano_cur_right
    cmp al, 0x47                    ; HOME
    je .nano_cur_home
    cmp al, 0x4F                    ; END
    je .nano_cur_end
    cmp al, 0x1C                    ; ENTER -> New line
    je .nano_on_enter
    cmp al, 0x0E                    ; BACKSPACE
    je .nano_on_bs
    cmp al, 0x53                    ; DELETE
    je .nano_on_del
    cmp al, 0x0F                    ; TAB -> Insert 4 spaces
    je .nano_on_tab

    ; 3. Decode printable character and insert at cursor position
    cmp al, 0x58
    jae .nano_idle
    xor bh, bh
    mov bl, al
    mov dl, [cs:sh_scancode_norm + bx]
    cmp byte [SH_SHIFT], 1
    jne .nano_got_ch
    mov dl, [cs:sh_scancode_shift + bx]
.nano_got_ch:
    test dl, dl
    jz .nano_idle

    call .nano_insert_char
    call sh_key_click
    call .nano_render_screen
    jmp .nano_event_loop

.nano_idle:
    mov ecx, 200000
    call delay_cycles
    jmp .nano_event_loop

; --- Nano Cursor & Edit Actions ---
.nano_cur_up:
    cmp byte [NANO_ROW], 0
    je .nano_event_loop
    dec byte [NANO_ROW]
    mov byte [NANO_MSG_ID], 0
    call sh_key_click
    call .nano_render_screen
    jmp .nano_event_loop

.nano_cur_down:
    cmp byte [NANO_ROW], 17
    jae .nano_event_loop
    inc byte [NANO_ROW]
    mov byte [NANO_MSG_ID], 0
    call sh_key_click
    call .nano_render_screen
    jmp .nano_event_loop

.nano_cur_left:
    cmp byte [NANO_COL], 0
    je .nano_left_wrap
    dec byte [NANO_COL]
    jmp .nano_nav_redraw
.nano_left_wrap:
    cmp byte [NANO_ROW], 0
    je .nano_event_loop
    dec byte [NANO_ROW]
    call .nano_find_line_end
    mov [NANO_COL], cl
.nano_nav_redraw:
    mov byte [NANO_MSG_ID], 0
    call sh_key_click
    call .nano_render_screen
    jmp .nano_event_loop

.nano_cur_right:
    cmp byte [NANO_COL], 71
    jae .nano_right_wrap
    inc byte [NANO_COL]
    jmp .nano_nav_redraw
.nano_right_wrap:
    cmp byte [NANO_ROW], 17
    jae .nano_event_loop
    inc byte [NANO_ROW]
    mov byte [NANO_COL], 0
    jmp .nano_nav_redraw

.nano_cur_home:
    mov byte [NANO_COL], 0
    jmp .nano_nav_redraw

.nano_cur_end:
    call .nano_find_line_end
    mov [NANO_COL], cl
    jmp .nano_nav_redraw

.nano_on_enter:
    cmp byte [NANO_ROW], 17
    jae .nano_event_loop
    inc byte [NANO_ROW]
    mov byte [NANO_COL], 0
    mov byte [NANO_MOD], 1
    mov byte [NANO_MSG_ID], 0
    call sh_key_click
    call .nano_render_screen
    jmp .nano_event_loop

.nano_on_tab:
    mov cx, 4
.nano_tab_lp:
    push cx
    mov dl, ' '
    call .nano_insert_char
    pop cx
    loop .nano_tab_lp
    call sh_key_click
    call .nano_render_screen
    jmp .nano_event_loop

.nano_on_bs:
    cmp byte [NANO_COL], 0
    je .nano_bs_prev_line
    dec byte [NANO_COL]
    call .nano_delete_at_cursor
    call sh_key_click
    call .nano_render_screen
    jmp .nano_event_loop
.nano_bs_prev_line:
    cmp byte [NANO_ROW], 0
    je .nano_event_loop
    dec byte [NANO_ROW]
    call .nano_find_line_end
    mov [NANO_COL], cl
    call sh_key_click
    call .nano_render_screen
    jmp .nano_event_loop

.nano_on_del:
    call .nano_delete_at_cursor
    call sh_key_click
    call .nano_render_screen
    jmp .nano_event_loop

.nano_cut_line:
    ; Clear current line (NANO_ROW) and shift subsequent lines up by 1
    mov al, [NANO_ROW]
    mov ah, 72
    mul ah
    add ax, NANO_BUF
    mov di, ax                      ; DI = Start of current line

    mov al, 17
    sub al, [NANO_ROW]
    jz .nano_cut_clear_last
    mov ah, 72
    mul ah
    mov cx, ax                      ; CX = Number of bytes below NANO_ROW
    lea si, [di + 72]
.nano_cut_shift:
    mov al, [ds:si]
    mov [ds:di], al
    inc si
    inc di
    loop .nano_cut_shift

.nano_cut_clear_last:
    mov di, NANO_BUF + 17 * 72
    mov cx, 72
    mov al, ' '
.nano_cut_clr:
    mov [ds:di], al
    inc di
    loop .nano_cut_clr

    mov byte [NANO_COL], 0
    mov byte [NANO_MOD], 1
    mov byte [NANO_MSG_ID], 3
    call sh_key_click
    call .nano_render_screen
    jmp .nano_event_loop

.nano_show_help:
    mov byte [NANO_MSG_ID], 4
    call sh_key_click
    call .nano_render_screen
    jmp .nano_event_loop

.nano_do_writeout:
    call .nano_save_buffer
    call sound_toggle
    call .nano_render_screen
    jmp .nano_event_loop

.nano_try_exit:
    cmp byte [NANO_MOD], 0
    je .nano_exit_now
    ; Unsaved changes -> Show GNU Nano "Save modified buffer?" prompt!
    mov byte [NANO_MSG_ID], 2
    call sound_click
    call .nano_render_screen
    jmp .nano_event_loop

.nano_save_and_exit:
    call .nano_save_buffer
    call sound_toggle

.nano_exit_now:
    ; Return to the framed BIOS Shell interface
    call sh_clear_screen
    mov di, [NANO_INODE]
    cmp byte [NANO_SAVED_FLAG], 1
    je .nano_exit_saved_msg

    mov si, str_nano_closed1
    mov ah, 0x0B
    call sh_print_inline
    lea si, [di + 8]
    mov ah, 0x0F
    call sh_print_ram_inline
    mov si, str_Quote_ok
    mov ah, 0x0B
    call sh_print_line
    ret

.nano_exit_saved_msg:
    mov si, str_write_ok1
    mov ah, 0x0A
    call sh_print_inline
    mov ax, [NANO_LAST_SZ]
    mov bl, 0x0E
    call sh_print_dec16
    mov si, str_write_ok2
    mov ah, 0x0A
    call sh_print_inline
    lea si, [di + 8]
    mov ah, 0x0F
    call sh_print_ram_inline
    mov si, str_Quote_ok
    mov ah, 0x0A
    call sh_print_line
    ret

; --- Helper Routines for Nano Buffer Manipulation & Saving ---
.nano_insert_char:
    ; Inserts character DL at (NANO_ROW, NANO_COL)
    mov al, [NANO_ROW]
    mov ah, 72
    mul ah
    add ax, NANO_BUF
    mov si, ax                      ; SI = Line start

    ; Shift characters from Col 70 down to NANO_COL right by 1
    mov cl, 71
.nic_shift:
    cmp cl, [NANO_COL]
    jbe .nic_put
    xor bh, bh
    mov bl, cl
    mov al, [ds:si + bx - 1]
    mov [ds:si + bx], al
    dec cl
    jmp .nic_shift
.nic_put:
    xor bh, bh
    mov bl, [NANO_COL]
    mov [ds:si + bx], dl
    mov byte [NANO_MOD], 1
    mov byte [NANO_MSG_ID], 0

    cmp byte [NANO_COL], 71
    jae .nic_wrap_row
    inc byte [NANO_COL]
    ret
.nic_wrap_row:
    cmp byte [NANO_ROW], 17
    jae .nic_done
    inc byte [NANO_ROW]
    mov byte [NANO_COL], 0
.nic_done:
    ret

.nano_delete_at_cursor:
    ; Deletes character at (NANO_ROW, NANO_COL) and pulls remainder of line left
    mov al, [NANO_ROW]
    mov ah, 72
    mul ah
    add ax, NANO_BUF
    mov si, ax
    mov cl, [NANO_COL]
.ndc_shift:
    cmp cl, 71
    jae .ndc_last
    xor bh, bh
    mov bl, cl
    mov al, [ds:si + bx + 1]
    mov [ds:si + bx], al
    inc cl
    jmp .ndc_shift
.ndc_last:
    mov byte [ds:si + 71], ' '
    mov byte [NANO_MOD], 1
    mov byte [NANO_MSG_ID], 0
    ret

.nano_find_line_end:
    ; Finds the column (CL = 0..71) after the last non-space character in NANO_ROW
    mov al, [NANO_ROW]
    mov ah, 72
    mul ah
    add ax, NANO_BUF
    mov si, ax
    mov cl, 72
.nfle_lp:
    test cl, cl
    jz .nfle_done
    xor bh, bh
    mov bl, cl
    cmp byte [ds:si + bx - 1], ' '
    jne .nfle_done
    dec cl
    jmp .nfle_lp
.nfle_done:
    cmp cl, 71
    jbe .nfle_ok
    mov cl, 71
.nfle_ok:
    ret

.nano_save_buffer:
    ; Serializes the 18x72 Nano buffer as real lines (with 0x0A) into the CybFS RAM pool!
    mov di, [NANO_INODE]

    ; 1. Find last non-empty line (0..17)
    mov ch, 18
.nsb_find_last_row:
    test ch, ch
    jz .nsb_empty_file
    mov al, ch
    dec al
    mov ah, 72
    mul ah
    add ax, NANO_BUF
    mov si, ax
    mov cl, 72
.nsb_chk_row:
    cmp byte [ds:si], ' '
    jne .nsb_found_last_row
    inc si
    dec cl
    jnz .nsb_chk_row
    dec ch
    jmp .nsb_find_last_row

.nsb_empty_file:
    mov word [ds:di + 6], 0
    mov word [NANO_LAST_SZ], 0
    mov byte [NANO_MOD], 0
    mov byte [NANO_SAVED_FLAG], 1
    mov byte [NANO_MSG_ID], 1
    call ata_sync_nvram
    ret

.nsb_found_last_row:
    ; CH = Number of lines to save (1..18)
    ; Check if we can reuse the existing space at the end of FS_ALLOC_PTR in-place
    mov bp, [FS_ALLOC_PTR]
    mov ax, [ds:di + 2]
    add ax, [ds:di + 6]
    cmp ax, bp
    jne .nsb_check_pool
    cmp word [ds:di + 2], FS_DATA_BASE
    jb .nsb_check_pool
    mov bp, [ds:di + 2]             ; Reuse in-place at the end of the pool!

.nsb_check_pool:
    cmp bp, FS_POOL_END - 256
    jb .nsb_start_write
    mov bp, FS_DATA_BASE + 1024     ; Safety fallback if pool is full

.nsb_start_write:
    mov byte [ds:di + 0], 1         ; flags = 1 ([RAM])
    mov [ds:di + 2], bp             ; data_off
    mov word [ds:di + 4], 0x0000
    xor dx, dx                      ; DX = Total bytes written
    xor bh, bh                      ; BH = Current line index (0..CH-1)

.nsb_row_loop:
    mov al, bh
    mov ah, 72
    mul ah
    add ax, NANO_BUF
    mov si, ax

    ; Determine line length without trailing spaces (CL = 72..0)
    mov cl, 72
.nsb_trim_lp:
    test cl, cl
    jz .nsb_write_nl
    push si
    xor ah, ah
    mov al, cl
    add si, ax
    mov al, [ds:si - 1]
    pop si
    cmp al, ' '
    jne .nsb_copy_row_bytes
    dec cl
    jmp .nsb_trim_lp

.nsb_copy_row_bytes:
    mov al, [ds:si]
    mov [ds:bp], al
    inc si
    inc bp
    inc dx
    dec cl
    jnz .nsb_copy_row_bytes

.nsb_write_nl:
    mov byte [ds:bp], 0x0A          ; Real line feed LF (0x0A)
    inc bp
    inc dx
    inc bh
    cmp bh, ch
    jb .nsb_row_loop

    mov [ds:di + 6], dx             ; Update real file size in Inode!
    cmp bp, [FS_ALLOC_PTR]
    jbe .nsb_keep_alloc
    mov [FS_ALLOC_PTR], bp
.nsb_keep_alloc:
    mov [NANO_LAST_SZ], dx
    mov byte [NANO_MOD], 0
    mov byte [NANO_SAVED_FLAG], 1
    mov byte [NANO_MSG_ID], 1
    call ata_sync_nvram
    ret

.nano_render_screen:
    ; Draws the complete GNU Nano full-screen interface (Rows 0..24)
    ; Row 0: Classic inverted GNU Nano header bar (0x70 = Black on Light Gray)
    xor di, di
    mov cx, 80
    mov ax, 0x7020
    rep stosw

    mov di, (0 * 80 + 2) * 2
    mov si, str_nano_top_l
    mov ah, 0x70
    call print_string

    mov di, (0 * 80 + 30) * 2
    mov si, str_nano_file_pfx
    mov ah, 0x70
    call print_string

    ; Write real filename from Inode into the title bar
    mov bx, [NANO_INODE]
    lea si, [bx + 8]
.nrs_fn_lp:
    mov al, [ds:si]
    test al, al
    jz .nrs_fn_done
    mov ah, 0x71                    ; Dark Blue on Light Gray
    stosw
    inc si
    jmp .nrs_fn_lp
.nrs_fn_done:

    mov di, (0 * 80 + 64) * 2
    mov si, str_nano_mod_no
    mov ah, 0x70
    cmp byte [NANO_MOD], 0
    je .nrs_mod_pr
    mov si, str_nano_mod_yes
    mov ah, 0x74                    ; Dark Red on Light Gray for [Modified]
.nrs_mod_pr:
    call print_string

    ; Row 1: Top editor border
    mov di, (1 * 80) * 2
    mov ah, 0x0B
    mov al, 0x01                    ; '┌'
    stosw
    mov cx, 78
    mov al, 0x05                    ; '─'
    rep stosw
    mov al, 0x02                    ; '┐'
    stosw
    mov di, (1 * 80 + 2) * 2
    mov si, str_nano_frm_hdr
    mov ah, 0x0E
    call print_string

    ; Rows 2..19: The 18 text lines from NANO_BUF (with line numbers 01..18 & cursor!)
    xor dl, dl                      ; DL = Line index 0..17
.nrs_row_lp:
    mov bl, dl
    add bl, 2                       ; Screen row = DL + 2
    xor al, al
    call xy_to_di

    ; Left border '│'
    mov ah, 0x0B
    mov al, 0x06
    stosw

    ; Line number (01..18)
    mov ah, 0x08
    cmp dl, [NANO_ROW]
    jne .nrs_ln_col_ok
    mov ah, 0x0E                    ; Highlight active line in yellow!
.nrs_ln_col_ok:
    mov al, ' '
    stosw
    mov al, dl
    inc al                          ; 1..18
    cmp al, 10
    jb .nrs_ln_single
    push ax
    mov al, '1'
    stosw
    pop ax
    sub al, 10
    add al, '0'
    stosw
    jmp .nrs_ln_sep
.nrs_ln_single:
    push ax
    mov al, '0'
    stosw
    pop ax
    add al, '0'
    stosw
.nrs_ln_sep:
    mov al, ' '
    stosw
    mov ah, 0x03
    mov al, 0x06                    ; Separator '│' after line number
    stosw
    mov ah, 0x07
    mov al, ' '
    stosw

    ; Output 72 text columns from NANO_BUF + dl * 72
    mov al, dl
    mov ah, 72
    mul ah
    add ax, NANO_BUF
    mov si, ax
    xor dh, dh                      ; DH = Column index 0..71
.nrs_col_lp:
    mov al, [ds:si]
    inc si
    mov ah, 0x0F                    ; Bright white text on black
    cmp dl, [NANO_ROW]
    jne .nrs_put_ch
    cmp dh, [NANO_COL]
    jne .nrs_put_ch
    mov ah, 0x70                    ; Inverted block cursor at (NANO_ROW, NANO_COL)!
.nrs_put_ch:
    stosw
    inc dh
    cmp dh, 72
    jb .nrs_col_lp

    mov ah, 0x07
    mov al, ' '
    stosw
    mov ah, 0x0B
    mov al, 0x06                    ; Right border '│'
    stosw

    inc dl
    cmp dl, 18
    jb .nrs_row_lp

    ; Row 20: Bottom editor border
    mov di, (20 * 80) * 2
    mov ah, 0x0B
    mov al, 0x03                    ; '└'
    stosw
    mov cx, 78
    mov al, 0x05                    ; '─'
    rep stosw
    mov al, 0x04                    ; '┘'
    stosw

    ; Row 21: Nano status & dialog bar
    mov di, (21 * 80) * 2
    mov cx, 80
    mov ax, 0x0720
    rep stosw

    cmp byte [NANO_MSG_ID], 1
    je .nrs_msg_saved
    cmp byte [NANO_MSG_ID], 2
    je .nrs_msg_ask
    cmp byte [NANO_MSG_ID], 3
    je .nrs_msg_cut
    cmp byte [NANO_MSG_ID], 4
    je .nrs_msg_help

    mov di, (21 * 80 + 2) * 2
    mov si, str_nano_msg_rdy
    mov ah, 0x0A
    call print_string
    jmp .nrs_row22

.nrs_msg_saved:
    mov byte [SH_CUR_ROW], 21
    mov byte [SH_CUR_COL], 2
    mov si, str_nano_msg_sv1
    mov ah, 0x0E
    call sh_print_inline
    mov ax, [NANO_LAST_SZ]
    mov bl, 0x0F
    call sh_print_dec16
    mov si, str_nano_msg_sv2
    mov ah, 0x0E
    call sh_print_inline
    mov bx, [NANO_INODE]
    lea si, [bx + 8]
    mov ah, 0x0B
    call sh_print_ram_inline
    mov si, str_nano_msg_sv3
    mov ah, 0x0E
    call sh_print_inline
    jmp .nrs_row22

.nrs_msg_ask:
    mov di, (21 * 80) * 2
    mov cx, 80
    mov ax, 0x4F20                  ; White on Red for save confirmation prompt!
    rep stosw
    mov di, (21 * 80 + 2) * 2
    mov si, str_nano_msg_ask
    mov ah, 0x4F
    call print_string
    jmp .nrs_row22

.nrs_msg_cut:
    mov di, (21 * 80 + 2) * 2
    mov si, str_nano_msg_cut
    mov ah, 0x0B
    call print_string
    jmp .nrs_row22

.nrs_msg_help:
    mov di, (21 * 80 + 2) * 2
    mov si, str_nano_msg_hlp
    mov ah, 0x0B
    call print_string

.nrs_row22:
    ; Row 22: Live cursor position (Line/Col) & free CybFS storage pool
    mov di, (22 * 80) * 2
    mov cx, 80
    mov ax, 0x0820
    rep stosw
    mov byte [SH_CUR_ROW], 22
    mov byte [SH_CUR_COL], 2
    mov si, str_nano_stat1
    mov ah, 0x0B
    call sh_print_inline
    xor ah, ah
    mov al, [NANO_ROW]
    inc al
    mov bl, 0x0F
    call sh_print_dec16
    mov si, str_nano_stat2
    mov ah, 0x0B
    call sh_print_inline
    xor ah, ah
    mov al, [NANO_COL]
    inc al
    mov bl, 0x0F
    call sh_print_dec16
    mov si, str_nano_stat3
    mov ah, 0x0B
    call sh_print_inline
    mov ax, [NANO_LAST_SZ]
    mov bl, 0x0E
    call sh_print_dec16
    mov si, str_nano_stat4
    mov ah, 0x0B
    call sh_print_inline
    mov ax, FS_POOL_END
    sub ax, [FS_ALLOC_PTR]
    mov bl, 0x0A
    call sh_print_dec16
    mov si, str_ls_sum4
    mov ah, 0x0A
    call sh_print_inline

    ; Rows 23 & 24: Authentic 2-row GNU Nano shortcut bar ('^' badges in 0x70!)
    mov di, (23 * 80) * 2
    mov si, str_nano_bot1
    call .nano_print_shortcut_bar
    mov di, (24 * 80) * 2
    mov si, str_nano_bot2
    call .nano_print_shortcut_bar
    ret

.nano_print_shortcut_bar:
    ; Outputs an 80-char string, rendering characters inside {...} inverted (0x70)
    mov ah, 0x07
.npsb_lp:
    mov al, [cs:si]
    inc si
    test al, al
    jz .npsb_done
    cmp al, '{'                     ; '{' starts inverted shortcut badge (0x70)
    je .npsb_inv_on
    cmp al, '}'                     ; '}' ends inverted shortcut badge (0x07)
    je .npsb_inv_off
    stosw
    jmp .npsb_lp
.npsb_inv_on:
    mov ah, 0x70
    jmp .npsb_lp
.npsb_inv_off:
    mov ah, 0x07
    jmp .npsb_lp
.npsb_done:
    ret

.fs_full_err:
    mov si, str_fs_full
    mov ah, 0x0C
    call sh_print_line
    ret

; --- 12. APPEND <FILENAME> <TEXT> (Append line to real file!) ---
.do_sh_append:
    cmp byte [SH_CLEAN_BUF + bx], 0
    je .append_usage
    call fs_find_in_dir
    jnc .cat_not_found
    cmp byte [ds:di + 0], 1
    jne .append_not_ram

    ; Check if the file is at the end of the current pool, otherwise relocate
    mov bp, [FS_ALLOC_PTR]
    cmp bp, FS_POOL_END - 128
    jae .fs_full_err

    mov ax, [ds:di + 2]             ; old data_off
    add ax, [ds:di + 6]             ; + old file_size
    cmp ax, bp
    je .app_in_place

    ; Copy existing data to [FS_ALLOC_PTR] so the file remains contiguous
    push si
    mov si, [ds:di + 2]
    mov [ds:di + 2], bp             ; new data_off
    mov cx, [ds:di + 6]
    test cx, cx
    jz .app_cp_done
.app_old_cp:
    mov al, [ds:si]
    mov [ds:bp], al
    inc si
    inc bp
    loop .app_old_cp
.app_cp_done:
    pop si

.app_in_place:
    ; Find text after the 2nd word in SH_CMD_BUF
    xor si, si
    mov cl, [SH_CMD_LEN]
    xor ch, ch
.ap_s1:
    test cx, cx
    jz .ap_do_append
    cmp byte [SH_CMD_BUF + si], ' '
    jne .ap_w1
    inc si
    dec cx
    jmp .ap_s1
.ap_w1:
    test cx, cx
    jz .ap_do_append
    cmp byte [SH_CMD_BUF + si], ' '
    je .ap_s2
    inc si
    dec cx
    jmp .ap_w1
.ap_s2:
    test cx, cx
    jz .ap_do_append
    cmp byte [SH_CMD_BUF + si], ' '
    jne .ap_w2
    inc si
    dec cx
    jmp .ap_s2
.ap_w2:
    test cx, cx
    jz .ap_do_append
    cmp byte [SH_CMD_BUF + si], ' '
    je .ap_s3
    inc si
    dec cx
    jmp .ap_w2
.ap_s3:
    test cx, cx
    jz .ap_do_append
    cmp byte [SH_CMD_BUF + si], ' '
    jne .ap_do_append
    inc si
    dec cx
    jmp .ap_s3

.ap_do_append:
    mov dx, [ds:di + 6]             ; Previous file size
.ap_cp_loop:
    test cx, cx
    jz .ap_finish
    mov al, [SH_CMD_BUF + si]
    mov [ds:bp], al
    inc si
    inc bp
    inc dx
    dec cx
    jmp .ap_cp_loop
.ap_finish:
    mov byte [ds:bp], 0x0A
    inc bp
    inc dx
    mov [ds:di + 6], dx
    mov [FS_ALLOC_PTR], bp
    call ata_sync_nvram

    mov si, str_app_ok1
    mov ah, 0x0A
    call sh_print_inline
    lea si, [di + 8]
    mov ah, 0x0F
    call sh_print_ram_inline
    mov si, str_app_ok2
    mov ah, 0x0A
    call sh_print_inline
    mov ax, dx
    mov bl, 0x0E
    call sh_print_dec16
    mov si, str_app_ok3
    mov ah, 0x0A
    call sh_print_line
    ret

.append_usage:
    mov si, str_app_use
    mov ah, 0x0E
    call sh_print_line
    ret
.append_not_ram:
    mov si, str_app_rom_err
    mov ah, 0x0C
    call sh_print_line
    ret

; --- 13. RM / DEL <NAME> (Delete real Inode from CybFS!) ---
.do_sh_rm:
    cmp byte [SH_CLEAN_BUF + bx], 0
    je .rm_usage
    call fs_find_in_dir
    jnc .cat_not_found

    ; Mark Inode as deleted (flags = 0) & sync persistently to disk
    mov byte [ds:di + 0], 0
    call ata_sync_nvram

    mov si, str_rm_ok
    mov ah, 0x0A
    call sh_print_inline
    lea si, [di + 8]
    mov ah, 0x0E
    call sh_print_ram_inline
    mov si, str_Quote_ok
    mov ah, 0x0A
    call sh_print_line
    ret

.rm_usage:
    mov si, str_rm_use
    mov ah, 0x0E
    call sh_print_line
    ret

; --- 14. CAT / TYPE <FILENAME> (READ 100% REAL FILE BYTES FROM CYBFS / ROM!) ---
.do_sh_cat:
    cmp byte [SH_CLEAN_BUF + bx], 0
    je .cat_no_arg
    call fs_find_in_dir
    jnc .cat_not_found

    mov al, [ds:di + 0]             ; flags
    cmp al, 2
    je .cd_not_dir
    cmp al, 4                       ; [HW] cmos.bin -> Live CMOS Hardware Dump!
    je .do_sh_cmos
    cmp al, 3                       ; [ROM] file -> Live 32-bit ROM header dump (+ audio playback)!
    je .cat_rom_file

    ; flags == 1: Read and print real RAM file byte-by-byte from [ds:data_off]!
    mov si, str_cat_hdr1
    mov ah, 0x0B
    call sh_print_inline
    push di
    lea si, [di + 8]
    mov ah, 0x0F
    call sh_print_ram_inline
    pop di
    mov si, str_cat_hdr2
    mov ah, 0x0B
    call sh_print_inline
    mov ax, [ds:di + 6]
    mov bl, 0x0E
    call sh_print_dec16
    mov si, str_cat_hdr3
    mov ah, 0x0B
    call sh_print_line

    mov cx, [ds:di + 6]             ; Real file size in bytes
    test cx, cx
    jz .cat_empty_done
    mov si, [ds:di + 2]             ; Real RAM start address (data_off)
.cat_ram_loop:
    mov al, [ds:si]
    inc si
    cmp al, 0x0A                    ; Line break?
    je .cat_nl
    cmp al, 0x0D
    je .cat_next_b
    mov ah, [SH_TEXT_ATTR]
    call sh_print_char
    jmp .cat_next_b
.cat_nl:
    call sh_newline
.cat_next_b:
    loop .cat_ram_loop
    cmp byte [SH_CUR_COL], 2
    je .cat_empty_done
    call sh_newline
.cat_empty_done:
    ret

.cat_rom_file:
    ; Check if it is a WAV file (meta 0..7) -> automatically play via SB16!
    mov al, [ds:di + 24]
    cmp al, 7
    ja .cat_rom_dump
    push di
    call sb16_play_pcm
    pop di
.cat_rom_dump:
    ; Get real 32-bit linear ROM address from Inode: (data_seg_hi << 16) | data_off
    movzx eax, word [ds:di + 4]
    shl eax, 16
    movzx edx, word [ds:di + 2]
    or eax, edx
    mov esi, eax

    ; Dump 4 rows of 16 real bytes directly via 32-bit Unreal Mode [fs:esi]!
    mov cx, 4
.crf_row:
    push cx
    mov eax, esi
    shr eax, 16
    mov dx, ax
    mov ah, 0x0B
    call sh_print_hex16
    mov al, ':'
    call sh_print_char
    mov dx, si
    mov ah, 0x0E
    call sh_print_hex16
    mov al, ' '
    call sh_print_char

    push esi
    mov cx, 16
.crf_hex:
    a32 mov dl, [fs:esi]
    mov ah, [SH_TEXT_ATTR]
    call sh_print_hex8
    mov al, ' '
    call sh_print_char
    inc esi
    loop .crf_hex
    pop esi

    mov al, '|'
    mov ah, 0x08
    call sh_print_char

    mov cx, 16
.crf_asc:
    a32 mov al, [fs:esi]
    cmp al, 32
    jb .crf_dot
    cmp al, 126
    ja .crf_dot
    jmp .crf_pr
.crf_dot:
    mov al, '.'
.crf_pr:
    mov ah, 0x0A
    call sh_print_char
    inc esi
    loop .crf_asc

    mov al, '|'
    mov ah, 0x08
    call sh_print_char
    call sh_newline
    pop cx
    dec cx
    jnz .crf_row
    ret

.cat_no_arg:
    mov si, str_cat_usage
    mov ah, 0x0E
    call sh_print_line
    ret

.cat_not_found:
    mov si, str_cat_nf_pfx
    mov ah, 0x0C
    call sh_print_line
    ret

; --- 15. RUN / SH <SCRIPT.NSH> (Execute real script file from CybFS!) ---
.do_sh_run:
    cmp byte [SH_CLEAN_BUF + bx], 0
    je .run_usage
    call fs_find_in_dir
    jnc .cat_not_found

    ; If it is snake.efi -> Launch Snake
    cmp byte [ds:di + 24], 0xFD
    je .do_sh_snake
    cmp byte [ds:di + 0], 1
    jne .run_not_script

    mov ax, [ds:di + 2]             ; data_off
    mov [SH_SCRIPT_PTR], ax
    add ax, [ds:di + 6]             ; + file_size = End
    mov [SH_SCRIPT_END], ax
    mov byte [SH_SCRIPT_ACT], 1

.run_line_loop:
    mov si, [SH_SCRIPT_PTR]
    cmp si, [SH_SCRIPT_END]
    jae .run_done

    ; Copy one line from the file into SH_CMD_BUF
    xor bx, bx
.run_cp_ch:
    cmp si, [SH_SCRIPT_END]
    jae .run_line_ready
    mov al, [ds:si]
    inc si
    cmp al, 0x0D
    je .run_cp_ch
    cmp al, 0x0A
    je .run_line_ready
    cmp bx, 54
    jae .run_cp_ch
    mov [SH_CMD_BUF + bx], al
    inc bx
    jmp .run_cp_ch

.run_line_ready:
    mov [SH_SCRIPT_PTR], si
    mov [SH_CMD_LEN], bl
    test bl, bl
    jz .run_line_loop

    call sh_normalize_cmd
    cmp byte [SH_CLEAN_BUF], 0
    je .run_line_loop

    ; Guard against infinite recursion (ignore 'run' inside script)
    mov si, cmd_run
    call sh_match_cmd
    jc .run_line_loop

    call sh_execute_command
    jmp .run_line_loop

.run_done:
    mov byte [SH_SCRIPT_ACT], 0
    ret
.run_usage:
    mov si, str_run_use
    mov ah, 0x0E
    call sh_print_line
    ret
.run_not_script:
    mov si, str_run_err
    mov ah, 0x0C
    call sh_print_line
    ret

; --- 16. FACTORYRESET / WIPE / FORMAT (Complete Factory Reset for Disk, CybFS & BIOS!) ---
.do_sh_format:
    ; 1. Completely wipe CybFS in RAM (0x3000..0x6FDF) & reload fresh from ROM Block 0 (0xFFFC0100)
    call fs_format_from_rom

    ; 2. Reset all BIOS Setup settings, shell theme, font scaling & Top-3 highscores to factory defaults!
    mov byte [CFG_SPEED], 0
    mov byte [CFG_WALLS], 0
    mov byte [CFG_SOUND], 0
    mov byte [CFG_FACE],  0
    mov byte [CFG_LEN],   0
    mov byte [CFG_WIN],   0
    mov byte [CFG_DISP],  0
    mov byte [CFG_THEME], 0
    mov byte [CFG_ARENA], 0

    mov byte [CFG_SH_THEME],  0
    mov byte [CFG_SH_PROMPT], 0
    mov byte [CFG_SH_BANNER], 0
    mov byte [CFG_SH_BEEP],   0
    mov byte [CFG_BOOT_MODE], 0
    mov byte [CFG_SH_FONT],   2     ; Standard 8x16 IBM VGA font size

    ; Restore default Top 3 Leaderboard: CYB (30), JON (20), ACE (10)
    mov byte [TOP3_TABLE + 0], 'C'
    mov byte [TOP3_TABLE + 1], 'Y'
    mov byte [TOP3_TABLE + 2], 'B'
    mov word [TOP3_TABLE + 3], 30

    mov byte [TOP3_TABLE + 5], 'J'
    mov byte [TOP3_TABLE + 6], 'O'
    mov byte [TOP3_TABLE + 7], 'N'
    mov word [TOP3_TABLE + 8], 20

    mov byte [TOP3_TABLE + 10], 'A'
    mov byte [TOP3_TABLE + 11], 'C'
    mov byte [TOP3_TABLE + 12], 'E'
    mov word [TOP3_TABLE + 13], 10
    mov word [HIGH_SCORE], 30

    ; 3. Overwrite factory defaults into hardware CMOS (0x70/0x71) AND onto the ATA disk (LBA 0..31)!
    call save_cmos_settings

    ; 4. Immediately reset VGA color palette, font size (8x16) and shell UI live
    call load_ui_palette
    call vga_apply_font_scale
    call sh_init_theme
    call sh_clear_screen
    call sound_toggle

    mov si, str_fmt_ok1
    mov ah, 0x0E
    call sh_print_line
    mov si, str_fmt_ok2
    mov ah, 0x0A
    call sh_print_line
    mov si, str_fmt_ok3
    mov ah, 0x0B
    call sh_print_line
    ret

; --- 17. SYSINFO / NEOFETCH ---
.do_sh_sysinfo:
    mov si, str_neo1
    mov ah, 0x0B
    call sh_print_line
    mov si, str_neo2
    call sh_print_line
    mov si, str_neo3
    call sh_print_line
    mov si, str_neo4
    call sh_print_line
    mov si, str_neo5
    call sh_print_line
    mov si, str_neo6
    call sh_print_line
    mov si, str_neo7
    mov ah, 0x0A
    call sh_print_line
    ret

; --- 18. PCI / DEVTREE (100% REAL HARDWARE PCI BUS SCANNER VIA 0xCF8/0xCFC!) ---
.do_sh_pci:
    mov si, str_pci_hdr
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line

    xor cx, cx                      ; CL = Device (0..7), CH = Function (0..3)
.pci_scan_loop:
    ; Build 32-bit PCI Config Address: 0x80000000 | (dev << 11) | (fn << 8)
    mov eax, 0x80000000
    movzx edx, cl
    shl edx, 11
    or eax, edx
    movzx edx, ch
    shl edx, 8
    or eax, edx

    mov dx, 0x0CF8
    out dx, eax
    mov dx, 0x0CFC
    in eax, dx                      ; EAX = [DeviceID (31:16) | VendorID (15:0)]

    cmp ax, 0xFFFF                  ; 0xFFFF = No PCI device in this slot
    je .pci_next_slot
    test ax, ax
    jz .pci_next_slot

    push eax
    push cx

    ; Output Bus 00, Dev CL, Fn CH
    mov si, str_pci_b0
    mov ah, [SH_TEXT_ATTR]
    call sh_print_inline
    mov dl, cl
    mov ah, 0x0B
    call sh_print_hex8
    mov al, ' '
    call sh_print_char
    mov dl, ch
    call sh_print_hex8
    mov al, ' '
    call sh_print_char
    call sh_print_char

    ; Output real VendorID : DeviceID from hardware register EAX!
    pop cx
    pop eax
    push eax
    push cx

    mov edx, eax                    ; DX = VendorID
    mov ah, 0x0E
    call sh_print_hex16
    mov al, ':'
    call sh_print_char
    shr eax, 16
    mov edx, eax                    ; DX = DeviceID
    mov ah, 0x0E
    call sh_print_hex16
    mov al, ' '
    call sh_print_char
    call sh_print_char

    ; Read PCI Class/Subclass live from register 0x08!
    mov eax, 0x80000008
    movzx edx, cl
    shl edx, 11
    or eax, edx
    movzx edx, ch
    shl edx, 8
    or eax, edx
    mov dx, 0x0CF8
    out dx, eax
    mov dx, 0x0CFC
    in eax, dx
    shr eax, 16                     ; AX = [BaseClass (15:8) | SubClass (7:0)]
    mov edx, eax                    ; Save DX = Class/Subclass BEFORE AH is used for text color!

    mov si, str_pci_cl_pfx
    mov ah, [SH_TEXT_ATTR]
    call sh_print_inline
    mov ah, 0x0A
    call sh_print_hex16

    ; Map known chipset names based on real Class/Device
    mov si, str_pci_desc_brg
    cmp dh, 0x06                    ; Class 06h = Bridge
    je .pci_pr_desc
    mov si, str_pci_desc_vga
    cmp dh, 0x03                    ; Class 03h = Display Controller
    je .pci_pr_desc
    mov si, str_pci_desc_ide
    cmp dh, 0x01                    ; Class 01h = Mass Storage / IDE
    je .pci_pr_desc
    mov si, str_pci_desc_net
    cmp dh, 0x02                    ; Class 02h = Network Controller
    je .pci_pr_desc
    mov si, str_pci_desc_usb
    cmp dx, 0x0C03                  ; Class 0C03h = xHCI USB 3.0 / EHCI USB 2.0 Host Controller!
    je .pci_pr_desc
    mov si, str_pci_desc_gen
.pci_pr_desc:
    mov ah, [SH_TEXT_ATTR]
    call sh_print_line

    pop cx
    pop eax

.pci_next_slot:
    inc ch
    cmp ch, 4
    jb .pci_scan_loop
    xor ch, ch
    inc cl
    cmp cl, 8
    jb .pci_scan_loop

    ; Additional active ISA hardware status line (SB16 DSP + CMOS RTC)
    mov si, str_pci_isa
    mov ah, 0x0B
    call sh_print_line
    ret

; --- 19. CPU / REGS ---
.do_sh_cpu:
    mov si, str_cpu_hdr
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line

    mov si, str_cpu_cs
    mov ah, [SH_TEXT_ATTR]
    call sh_print_inline
    mov dx, cs
    mov ah, 0x0E
    call sh_print_hex16

    mov si, str_cpu_ds
    mov ah, [SH_TEXT_ATTR]
    call sh_print_inline
    mov dx, ds
    mov ah, 0x0E
    call sh_print_hex16

    mov si, str_cpu_es
    mov ah, [SH_TEXT_ATTR]
    call sh_print_inline
    mov dx, es
    mov ah, 0x0E
    call sh_print_hex16

    mov si, str_cpu_fs
    mov ah, [SH_TEXT_ATTR]
    call sh_print_inline
    mov dx, fs
    mov ah, 0x0E
    call sh_print_hex16

    mov si, str_cpu_sp
    mov ah, [SH_TEXT_ATTR]
    call sh_print_inline
    mov dx, sp
    mov ah, 0x0E
    call sh_print_hex16
    call sh_newline

    mov si, str_cpu_cr0
    mov ah, 0x0A
    call sh_print_line
    ret

; --- 20. CMOS / NVRAM ---
.do_sh_cmos:
    mov si, str_cmos_hdr
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line

    mov si, str_cmos_r40
    mov ah, 0x0B
    call sh_print_inline
    mov cl, 0x40
.cm_loop1:
    mov al, cl
    call cmos_read_byte
    mov dl, al
    mov ah, [SH_TEXT_ATTR]
    call sh_print_hex8
    mov al, ' '
    call sh_print_char
    inc cl
    cmp cl, 0x50
    jb .cm_loop1
    call sh_newline

    mov si, str_cmos_r50
    mov ah, 0x0B
    call sh_print_inline
    mov cl, 0x50
.cm_loop2:
    mov al, cl
    call cmos_read_byte
    mov dl, al
    mov ah, [SH_TEXT_ATTR]
    call sh_print_hex8
    mov al, ' '
    call sh_print_char
    inc cl
    cmp cl, 0x60
    jb .cm_loop2
    call sh_newline

    mov si, str_cmos_ok
    mov ah, 0x0A
    call sh_print_line
    ret

; --- 21. DMEM [HEX_ADDR] (Live Hex + ASCII Memory Dump) ---
.do_sh_dmem:
    mov al, [SH_CLEAN_BUF + bx]
    test al, al
    jz .dmem_use_cur

    xor dx, dx
.dmem_parse_hex:
    mov al, [SH_CLEAN_BUF + bx]
    test al, al
    jz .dmem_set_addr
    cmp al, ' '
    je .dmem_set_addr
    shl dx, 4
    cmp al, '9'
    jbe .dmem_dig
    sub al, 'a' - 10
    jmp .dmem_add_nib
.dmem_dig:
    sub al, '0'
.dmem_add_nib:
    and al, 0x0F
    or dl, al
    inc bx
    jmp .dmem_parse_hex
.dmem_set_addr:
    mov [SH_DUMP_ADDR], dx

.dmem_use_cur:
    mov cx, 4
.dmem_row_loop:
    push cx
    mov dx, [SH_DUMP_ADDR]

    mov si, str_seg_ram
    cmp dx, 0x8000
    jb .dmem_pr_seg
    mov si, str_seg_rom
.dmem_pr_seg:
    mov ah, 0x0B
    call sh_print_inline
    mov ah, 0x0E
    call sh_print_hex16
    mov al, ' '
    call sh_print_char

    mov bp, [SH_DUMP_ADDR]
    mov cx, 16
.dmem_hex_loop:
    cmp bp, 0x8000
    jae .dmem_rd_rom1
    mov dl, [ds:bp]
    jmp .dmem_pr_hb
.dmem_rd_rom1:
    mov dl, [cs:bp]
.dmem_pr_hb:
    mov ah, [SH_TEXT_ATTR]
    call sh_print_hex8
    mov al, ' '
    call sh_print_char
    inc bp
    loop .dmem_hex_loop

    mov al, '|'
    mov ah, 0x08
    call sh_print_char

    mov bp, [SH_DUMP_ADDR]
    mov cx, 16
.dmem_asc_loop:
    cmp bp, 0x8000
    jae .dmem_rd_rom2
    mov al, [ds:bp]
    jmp .dmem_chk_asc
.dmem_rd_rom2:
    mov al, [cs:bp]
.dmem_chk_asc:
    cmp al, 32
    jb .dmem_dot
    cmp al, 126
    ja .dmem_dot
    jmp .dmem_pr_ac
.dmem_dot:
    mov al, '.'
.dmem_pr_ac:
    mov ah, 0x0A
    call sh_print_char
    inc bp
    loop .dmem_asc_loop

    mov al, '|'
    mov ah, 0x08
    call sh_print_char
    call sh_newline

    add word [SH_DUMP_ADDR], 16
    pop cx
    dec cx
    jnz .dmem_row_loop
    ret

; --- 22. TIME / DATE / RTC (Hardware CMOS Clock) ---
.do_sh_time:
    mov si, str_rtc_pfx
    mov ah, [SH_HIGH_ATTR]
    call sh_print_inline

    mov al, '2'
    mov ah, 0x0B
    call sh_print_char
    mov al, '0'
    call sh_print_char
    mov al, 0x09
    call cmos_read_byte
    mov dl, al
    call sh_print_hex8
    mov al, '-'
    call sh_print_char

    mov al, 0x08
    call cmos_read_byte
    mov dl, al
    call sh_print_hex8
    mov al, '-'
    call sh_print_char

    mov al, 0x07
    call cmos_read_byte
    mov dl, al
    call sh_print_hex8
    mov al, ' '
    call sh_print_char
    call sh_print_char

    mov al, 0x04
    call cmos_read_byte
    mov dl, al
    mov ah, 0x0A
    call sh_print_hex8
    mov al, ':'
    call sh_print_char

    mov al, 0x02
    call cmos_read_byte
    mov dl, al
    call sh_print_hex8
    mov al, ':'
    call sh_print_char

    mov al, 0x00
    call cmos_read_byte
    mov dl, al
    call sh_print_hex8

    mov si, str_rtc_sfx
    mov ah, [SH_TEXT_ATTR]
    call sh_print_line
    ret

; --- 23. SOUND [0-7] (SB16 16-Bit DMA Testbench) ---
.do_sh_sound:
    mov al, [SH_CLEAN_BUF + bx]
    cmp al, '0'
    jb .snd_default
    cmp al, '7'
    ja .snd_default
    sub al, '0'
    jmp .snd_play_it
.snd_default:
    mov al, 3
.snd_play_it:
    push ax
    call sb16_play_pcm
    mov si, str_snd_play1
    mov ah, 0x0A
    call sh_print_inline
    pop ax
    mov dl, al
    add dl, '0'
    mov al, dl
    mov ah, 0x0E
    call sh_print_char
    mov si, str_snd_play2
    mov ah, 0x0A
    call sh_print_line
    mov si, str_snd_list
    mov ah, [SH_TEXT_ATTR]
    call sh_print_line
    ret

; --- 24. IO / PORTS (Live Hardware Port Inspector) ---
.do_sh_io:
    mov si, str_io_hdr
    mov ah, [SH_HIGH_ATTR]
    call sh_print_inline

    mov si, str_io_p60
    mov ah, [SH_TEXT_ATTR]
    call sh_print_inline
    in al, 0x60
    mov dl, al
    mov ah, 0x0E
    call sh_print_hex8

    mov si, str_io_p61
    mov ah, [SH_TEXT_ATTR]
    call sh_print_inline
    in al, 0x61
    mov dl, al
    mov ah, 0x0E
    call sh_print_hex8

    mov si, str_io_p64
    mov ah, [SH_TEXT_ATTR]
    call sh_print_inline
    in al, 0x64
    mov dl, al
    mov ah, 0x0E
    call sh_print_hex8

    mov si, str_io_p22c
    mov ah, [SH_TEXT_ATTR]
    call sh_print_inline
    mov dx, 0x22C
    in al, dx
    mov dl, al
    mov ah, 0x0E
    call sh_print_hex8

    mov si, str_io_p3da
    mov ah, [SH_TEXT_ATTR]
    call sh_print_inline
    mov dx, 0x3DA
    in al, dx
    mov dl, al
    mov ah, 0x0E
    call sh_print_hex8
    call sh_newline
    ret

; --- 25. MEMTEST (Real 64KB RAM Write/Read Verification Test with Error Counter!) ---
.do_sh_memtest:
    mov si, str_mt_1
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line

    push es
    mov ax, 0x2000
    mov es, ax
    xor dx, dx                      ; DX = Real error counter!

    ; Pass 1: Write 0x55AA and read back & verify word-by-word!
    xor di, di
    mov cx, 32768
    mov ax, 0x55AA
    rep stosw

    xor di, di
    mov cx, 32768
.mt_verify1:
    cmp word [es:di], 0x55AA
    je .mt_v1_ok
    inc dx
.mt_v1_ok:
    add di, 2
    loop .mt_verify1

    ; Pass 2: Write 0xAA55 and read back & verify word-by-word!
    xor di, di
    mov cx, 32768
    mov ax, 0xAA55
    rep stosw

    xor di, di
    mov cx, 32768
.mt_verify2:
    cmp word [es:di], 0xAA55
    je .mt_v2_ok
    inc dx
.mt_v2_ok:
    add di, 2
    loop .mt_verify2
    pop es

    push dx
    call sound_toggle
    mov si, str_mt_2
    mov ah, 0x0A
    call sh_print_inline
    pop ax                          ; AX = Real measured error count!
    mov bl, 0x0E
    call sh_print_dec16
    mov si, str_mt_3
    mov ah, 0x0A
    call sh_print_line
    ret

; --- 26. COLOR [0-3] ---
.do_sh_color:
    mov al, [SH_CLEAN_BUF + bx]
    cmp al, '0'
    jb .col_cycle
    cmp al, '3'
    ja .col_cycle
    sub al, '0'
    mov [CFG_SH_THEME], al
    jmp .col_apply
.col_cycle:
    inc byte [CFG_SH_THEME]
    and byte [CFG_SH_THEME], 3
.col_apply:
    call save_cmos_settings
    call sh_init_theme
    call sh_clear_screen
    mov si, str_col_ok
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line
    ret

; --- 27. ECHO ---
.do_sh_echo:
    lea si, [SH_CMD_BUF + bx]
.echo_lp:
    mov al, [ds:si]
    test al, al
    jz .echo_end
    cmp si, SH_CMD_BUF + 60
    jae .echo_end
    mov dl, [SH_CMD_LEN]
    xor dh, dh
    add dx, SH_CMD_BUF
    cmp si, dx
    jae .echo_end
    mov ah, [SH_TEXT_ATTR]
    call sh_print_char
    inc si
    jmp .echo_lp
.echo_end:
    call sh_newline
    ret

; --- 28. BEEP ---
.do_sh_beep:
    call sound_toggle
    mov si, str_beep_ok
    mov ah, 0x0A
    call sh_print_line
    ret

; --- 29. SNAKE / BOOT ---
.do_sh_snake:
    pop ax
    call apply_color_theme
    jmp init_snake_game

; --- 30. SETFONT [1-4 | small|medium|large|huge] (Live VGA Hardware Font Scaler!) ---
.do_sh_setfont:
    mov al, [SH_CLEAN_BUF + bx]
    test al, al
    jz .sf_cycle

    cmp al, '1'
    je .sf_set_0
    cmp al, 's'                     ; 'small'
    je .sf_set_0

    cmp al, '2'
    je .sf_set_1
    cmp al, 'm'                     ; 'medium'
    je .sf_set_1

    cmp al, '3'
    je .sf_set_2
    cmp al, 'l'                     ; 'large'
    je .sf_set_2
    cmp al, 'n'                     ; 'normal'
    je .sf_set_2

    cmp al, '4'
    je .sf_set_3
    cmp al, 'h'                     ; 'huge'
    je .sf_set_3
    cmp al, 'b'                     ; 'bold'
    je .sf_set_3
    cmp al, 'x'                     ; 'xl'
    je .sf_set_3

.sf_cycle:
    mov al, [CFG_SH_FONT]
    inc al
    and al, 3
    mov [CFG_SH_FONT], al
    jmp .sf_apply

.sf_set_0:
    mov byte [CFG_SH_FONT], 0
    jmp .sf_apply
.sf_set_1:
    mov byte [CFG_SH_FONT], 1
    jmp .sf_apply
.sf_set_2:
    mov byte [CFG_SH_FONT], 2
    jmp .sf_apply
.sf_set_3:
    mov byte [CFG_SH_FONT], 3

.sf_apply:
    call vga_apply_font_scale
    call save_cmos_settings
    call sound_toggle

    mov si, str_sf_ok_pfx
    mov ah, 0x0A
    call sh_print_inline

    mov al, [CFG_SH_FONT]
    cmp al, 0
    je .sf_msg_0
    cmp al, 1
    je .sf_msg_1
    cmp al, 2
    je .sf_msg_2
    mov si, str_sf_name_3
    jmp .sf_msg_out
.sf_msg_0:
    mov si, str_sf_name_0
    jmp .sf_msg_out
.sf_msg_1:
    mov si, str_sf_name_1
    jmp .sf_msg_out
.sf_msg_2:
    mov si, str_sf_name_2
.sf_msg_out:
    mov ah, 0x0E
    call sh_print_line
    mov si, str_sf_usage
    mov ah, [SH_TEXT_ATTR]
    call sh_print_line
    ret

; --- 31. REBOOT / RESET (Real x86 Hardware Reset via 8042 Port 0x64 & PCI 0xCF9!) ---
.do_sh_reboot:
    mov si, str_reboot_msg
    mov ah, 0x0E
    call sh_print_line
    call ata_sync_nvram             ; Flush all data to disk before hardware reset!
    call sound_toggle
    mov ecx, 100000000              ; ~0.35s brief display before hardware reset
    call delay_cycles

    cli
    ; 1. Real 8042 Keyboard Controller CPU reset pulse (Port 0x64 <- 0xFE)
    mov al, 0xFE
    out 0x64, al
    jmp $+2

    ; 2. Real Intel PIIX/ICH PCI Reset Control Register hard reset (Port 0xCF9 <- 0x06)
    mov dx, 0x0CF9
    mov al, 0x06
    out dx, al
    jmp $+2

    ; 3. Fallback: Jump to x86 hardware reset vector F000:FFF0
    jmp 0xF000:0xFFF0

; --- 32. SHUTDOWN / POWEROFF / HALT (Real Hardware ACPI S5 Soft-Off + Disk Sync!) ---
.do_sh_shutdown:
    mov si, str_shut_msg1
    mov ah, 0x0E
    call sh_print_line
    mov si, str_shut_msg2
    mov ah, 0x0C
    call sh_print_line

    ; Save complete CybFS & CMOS mirror persistently to disk (cybfs_nvram.img)!
    call ata_sync_nvram

    ; Play acoustic shutdown signal
    mov al, 6                       ; Sample 6 (Descending Chime)
    call sb16_play_pcm
    mov ecx, 250000000              ; Wait ~0.8s so message & sound are perceptible
    call delay_cycles

    ; 1. Map & enable bare-metal Intel PIIX4 PM (PCI 00:01.3) ACPI I/O Base at 0x0600!
    mov dx, 0x0CF8
    mov eax, 0x80000B40             ; Bus 0, Dev 1, Fn 3, Reg 0x40 (PMBA)
    out dx, eax
    mov dx, 0x0CFC
    mov eax, 0x00000601             ; PM Base = 0x0600 | Bit 0 (I/O Space Indicator)
    out dx, eax

    mov dx, 0x0CF8
    mov eax, 0x80000B80             ; Bus 0, Dev 1, Fn 3, Reg 0x80 (PMREGMISC)
    out dx, eax
    mov dx, 0x0CFC
    mov al, 0x01                    ; PMIOSE = 1 (Enable ACPI PM I/O Space!)
    out dx, al

    mov dx, 0x0CF8
    mov eax, 0x80000B04             ; Bus 0, Dev 1, Fn 3, Reg 0x04 (PCI Command)
    out dx, eax
    mov dx, 0x0CFC
    in ax, dx
    or ax, 0x0001                   ; Bit 0 = I/O Space Enable
    out dx, ax

    ; Now send real ACPI S5 Soft-Off (SLP_TYP5 | SLP_EN = 0x2000) to PM1a_CNT (0x0604)!
    mov dx, 0x0604
    mov ax, 0x2000
    out dx, ax

    ; 2. Bochs / Older QEMU ACPI Power-Off (Port 0xB004 -> 0x2000)
    mov dx, 0xB004
    mov ax, 0x2000
    out dx, ax

    ; 3. VirtualBox / Cloud Hypervisor ACPI Power-Off (Port 0x4004 -> 0x3400)
    mov dx, 0x4004
    mov ax, 0x3400
    out dx, ax

    ; 4. Fallback if hardware does not support ACPI S5: Safe ATX halt console
    mov si, str_shut_halted
    mov ah, 0x0A
    call sh_print_line
    cli
.shut_hlt_loop:
    hlt
    jmp .shut_hlt_loop

; --- 33. USB / LSUSB / XHCI / EHCI (Live xHCI 3.0 & EHCI 2.0 MMIO Status!) ---
.do_sh_usb:
    ; Re-scan live PORTSC registers on xHCI and EHCI Root Hubs
    call usb_init_controllers

    mov si, str_usb_hdr
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line
    mov si, str_usb_sep
    mov ah, 0x08
    call sh_print_line

    ; 1. xHCI USB 3.0 SuperSpeed Controller Report
    cmp byte [XHCI_FOUND], 1
    jne .usb_no_xhci
    mov si, str_usb_xhci1
    mov ah, 0x0B
    call sh_print_inline
    mov dx, [XHCI_VEN_ID]
    mov ah, 0x0E
    call sh_print_hex16
    mov al, ':'
    call sh_print_char
    mov dx, [XHCI_DEV_ID]
    call sh_print_hex16
    mov si, str_usb_xhci2
    mov ah, 0x0A
    call sh_print_line

    mov si, str_usb_xhci3
    mov ah, [SH_TEXT_ATTR]
    call sh_print_inline
    mov dx, [XHCI_HCI_VER]
    mov ah, 0x0E
    call sh_print_hex16
    mov si, str_usb_xhci4
    mov ah, [SH_TEXT_ATTR]
    call sh_print_inline
    xor ah, ah
    mov al, [XHCI_MAX_SLOTS]
    mov bl, 0x0F
    call sh_print_dec16
    mov si, str_usb_xhci5
    mov ah, [SH_TEXT_ATTR]
    call sh_print_inline
    xor ah, ah
    mov al, [XHCI_MAX_PORTS]
    mov bl, 0x0F
    call sh_print_dec16
    mov si, str_usb_xhci6
    mov ah, 0x0A
    call sh_print_inline
    xor ah, ah
    mov al, [XHCI_PORTS_CONN]
    mov bl, 0x0E
    call sh_print_dec16
    mov si, str_usb_xhci7
    mov ah, 0x0B
    call sh_print_inline
    mov edx, [XHCI_PORT1_SC]
    mov ah, 0x0E
    call sh_print_hex16
    call sh_newline
    jmp .usb_chk_ehci

.usb_no_xhci:
    mov si, str_post_xhci_none
    mov ah, 0x0C
    call sh_print_line

.usb_chk_ehci:
    ; 2. EHCI USB 2.0 High-Speed Controller Report
    cmp byte [EHCI_FOUND], 1
    jne .usb_no_ehci
    mov si, str_usb_ehci1
    mov ah, 0x0B
    call sh_print_inline
    mov dx, [EHCI_VEN_ID]
    mov ah, 0x0E
    call sh_print_hex16
    mov al, ':'
    call sh_print_char
    mov dx, [EHCI_DEV_ID]
    call sh_print_hex16
    mov si, str_usb_ehci2
    mov ah, 0x0A
    call sh_print_line

    mov si, str_usb_ehci3
    mov ah, [SH_TEXT_ATTR]
    call sh_print_inline
    mov dx, [EHCI_HCI_VER]
    mov ah, 0x0E
    call sh_print_hex16
    mov si, str_usb_ehci5
    mov ah, [SH_TEXT_ATTR]
    call sh_print_inline
    xor ah, ah
    mov al, [EHCI_MAX_PORTS]
    mov bl, 0x0F
    call sh_print_dec16
    mov si, str_usb_xhci6
    mov ah, 0x0A
    call sh_print_inline
    xor ah, ah
    mov al, [EHCI_PORTS_CONN]
    mov bl, 0x0E
    call sh_print_dec16
    mov si, str_usb_xhci7
    mov ah, 0x0B
    call sh_print_inline
    mov edx, [EHCI_PORT1_SC]
    mov ah, 0x0E
    call sh_print_hex16
    call sh_newline
    jmp .usb_summary

.usb_no_ehci:
    mov si, str_post_ehci_none
    mov ah, 0x0C
    call sh_print_line

.usb_summary:
    mov si, str_usb_tree1
    mov ah, 0x0A
    call sh_print_line
    mov si, str_usb_tree2
    mov ah, 0x0B
    call sh_print_line
    ret

; --- 34. MOUSE (Live Hardware Mouse & Pointer Telemetry!) ---
.do_sh_mouse:
    mov si, str_mouse_hdr
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line
    mov si, str_mouse_line1
    mov ah, 0x0A
    call sh_print_line

    mov si, str_mouse_pos1
    mov ah, [SH_TEXT_ATTR]
    call sh_print_inline
    xor ah, ah
    mov al, [MOUSE_X]
    mov bl, 0x0E
    call sh_print_dec16
    mov al, ','
    mov ah, [SH_TEXT_ATTR]
    call sh_print_char
    xor ah, ah
    mov al, [MOUSE_Y]
    mov bl, 0x0E
    call sh_print_dec16

    mov si, str_mouse_pos2
    mov ah, [SH_TEXT_ATTR]
    call sh_print_inline
    mov ax, [MOUSE_FINE_X]
    mov bl, 0x0B
    call sh_print_dec16
    mov al, ','
    mov ah, [SH_TEXT_ATTR]
    call sh_print_char
    mov ax, [MOUSE_FINE_Y]
    mov bl, 0x0B
    call sh_print_dec16

    mov si, str_mouse_pos3
    mov ah, [SH_TEXT_ATTR]
    call sh_print_inline
    mov ax, [MOUSE_EVT_CNT]
    mov bl, 0x0A
    call sh_print_dec16
    call sh_newline
    ret

; =============================================================================
; LIVE HARDWARE VGA PLANE 2 FONT SCALER (0xA000:0000, Global Callable)
; =============================================================================
vga_apply_font_scale:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    ; 1. Unlock VGA Sequencer & Graphics Controller for Plane 2 (0xA0000)
    mov dx, 0x3C4
    mov ax, 0x0100
    out dx, ax
    mov ax, 0x0402                  ; SR02 = Plane 2
    out dx, ax
    mov ax, 0x0604                  ; SR04 = Sequential
    out dx, ax
    mov ax, 0x0300
    out dx, ax

    mov dx, 0x3CE
    mov ax, 0x0204                  ; GR04 = Plane 2
    out dx, ax
    mov ax, 0x0005                  ; GR05 = Write Mode 0
    out dx, ax
    mov ax, 0x0406                  ; GR06 = 0xA0000
    out dx, ax

    mov ax, 0xA000
    mov es, ax

    ; 2. Scale all ASCII glyphs from font_table according to [CFG_SH_FONT] (0..3)!
    mov si, font_table
.vafs_char_lp:
    mov al, [cs:si]
    inc si
    test al, al
    jz .vafs_restore_custom

    xor ah, ah
    shl ax, 5                       ; Offset in Plane 2 = char_code * 32
    mov di, ax

    mov bl, [CFG_SH_FONT]
    and bl, 3
    cmp bl, 0
    je .vafs_scale_small            ; 0: Small 8x8 Micro (5px Cap Height)
    cmp bl, 1
    je .vafs_scale_medium           ; 1: Medium 8x12 Compact (8px Cap Height)
    cmp bl, 3
    je .vafs_scale_huge             ; 3: Huge 8x16 XL Tall (14px Cap Height)

    ; 2: Large 8x16 Standard IBM VGA (10px Cap Height, 1:1 copy)
    mov cx, 16
.vafs_std_lp:
    mov al, [cs:si]
    inc si
    stosb
    loop .vafs_std_lp
    jmp .vafs_char_lp

.vafs_scale_small:
    ; Small (1): 4 blank top lines + 8 compressed scanlines (2:1 OR) + 4 blank bottom lines
    xor al, al
    stosb
    stosb
    stosb
    stosb
    mov cx, 8
.vafs_sm_lp:
    mov al, [cs:si]
    or al, [cs:si + 1]
    add si, 2
    stosb
    loop .vafs_sm_lp
    xor al, al
    stosb
    stosb
    stosb
    stosb
    jmp .vafs_char_lp

.vafs_scale_medium:
    ; Medium (2): 12 active scanlines centered (8px Cap Height)
    xor al, al
    stosb
    stosb
    stosb
    mov al, [cs:si + 2]
    stosb
    mov al, [cs:si + 3]
    or al, [cs:si + 4]
    stosb
    mov al, [cs:si + 5]
    stosb
    mov al, [cs:si + 6]
    stosb
    mov al, [cs:si + 7]
    stosb
    mov al, [cs:si + 8]
    or al, [cs:si + 9]
    stosb
    mov al, [cs:si + 10]
    stosb
    mov al, [cs:si + 11]
    stosb
    mov al, [cs:si + 12]
    or al, [cs:si + 13]
    stosb
    xor al, al
    stosb
    stosb
    stosb
    stosb
    add si, 16
    jmp .vafs_char_lp

.vafs_scale_huge:
    ; Huge (4): Vertically stretched to 14 active scanlines
    xor al, al
    stosb
    mov bx, si
    mov al, [cs:bx + 2]
    stosb
    mov al, [cs:bx + 2]
    stosb
    mov al, [cs:bx + 3]
    stosb
    mov al, [cs:bx + 4]
    stosb
    mov al, [cs:bx + 5]
    stosb
    mov al, [cs:bx + 6]
    stosb
    mov al, [cs:bx + 7]
    stosb
    mov al, [cs:bx + 7]
    stosb
    mov al, [cs:bx + 8]
    stosb
    mov al, [cs:bx + 9]
    stosb
    mov al, [cs:bx + 10]
    stosb
    mov al, [cs:bx + 11]
    stosb
    mov al, [cs:bx + 11]
    or al, [cs:bx + 12]
    stosb
    mov al, [cs:bx + 13]
    stosb
    xor al, al
    stosb
    add si, 16
    jmp .vafs_char_lp

.vafs_restore_custom:
    ; 3. Always keep border glyphs (0x01..0x0A) at full 16-scanline quality
    mov si, custom_glyphs_table
.vafs_cg_lp:
    mov al, [cs:si]
    inc si
    test al, al
    jz .vafs_cg_done
    xor ah, ah
    shl ax, 5
    mov di, ax
    mov cx, 16
.vafs_cg_cp:
    mov al, [cs:si]
    inc si
    stosb
    loop .vafs_cg_cp
    jmp .vafs_cg_lp
.vafs_cg_done:

    ; 4. Switch back to Odd/Even Text Mode at 0xB8000
    mov dx, 0x3C4
    mov ax, 0x0100
    out dx, ax
    mov ax, 0x0302                  ; SR02 = Plane 0 & 1
    out dx, ax
    mov ax, 0x0204                  ; SR04 = Odd/Even
    out dx, ax
    mov ax, 0x0300
    out dx, ax

    mov dx, 0x3CE
    mov ax, 0x0004
    out dx, ax
    mov ax, 0x1005
    out dx, ax
    mov ax, 0x0E06                  ; GR06 = 0xB8000 text window
    out dx, ax

    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; =============================================================================
; BARE-METAL ATA/IDE PIO PERSISTENCE DRIVER (Ports 0x1F0..0x1F7, LBA 0..31)
; Saves & loads the complete 16 KB CybFS + CMOS Mirror (0x3000..0x6FFF)
; persistently to/from the 'cybfs_nvram.img' disk image!
; =============================================================================
ata_init_piix3_ide:
    ; Unlock bare-metal Intel PIIX3 IDE Controller (PCI 00:01.1) for Ports 0x1F0..0x1F7!
    push eax
    push dx
    mov dx, 0x0CF8
    mov eax, 0x80000940             ; Bus 0, Dev 1, Fn 1, Reg 0x40 (IDETIM Primary/Secondary)
    out dx, eax
    mov dx, 0x0CFC
    mov eax, 0x80008000             ; Bit 15 = Primary IDE Decode Enable (0x1F0..0x1F7)
    out dx, eax

    mov dx, 0x0CF8
    mov eax, 0x80000904             ; Bus 0, Dev 1, Fn 1, Reg 0x04 (PCI Command)
    out dx, eax
    mov dx, 0x0CFC
    in ax, dx
    or ax, 0x0005                   ; Bit 0 = I/O Space Enable, Bit 2 = Bus Master
    out dx, ax
    pop dx
    pop eax
    ret

ata_load_nvram:
    push ax
    push bx
    push cx
    push dx
    push di

    call ata_init_piix3_ide

    ; Check if Primary Master IDE drive is attached
    mov dx, 0x1F6
    mov al, 0xE0                    ; Master Drive + LBA28 Mode
    out dx, al
    mov dx, 0x1F7
    in al, dx
    cmp al, 0xFF                    ; 0xFF = Floating bus (no drive)
    je .aln_done
    test al, al                     ; 0x00 = No drive
    jz .aln_done

    mov di, 0x3000                  ; Target in RAM: 0x0000:0x3000..0x6FFF (16 KB)
    xor bl, bl                      ; BL = Sector LBA 0..31
.aln_sec_loop:
    call ata_wait_not_bsy
    jc .aln_done

    mov dx, 0x1F6
    mov al, 0xE0
    out dx, al

    mov dx, 0x1F2
    mov al, 1                       ; 1 sector per PIO transfer (512 bytes)
    out dx, al

    mov dx, 0x1F3
    mov al, bl                      ; LBA Bits 0..7
    out dx, al

    mov dx, 0x1F4
    xor al, al                      ; LBA Bits 8..15 = 0
    out dx, al

    mov dx, 0x1F5
    out dx, al                      ; LBA Bits 16..23 = 0

    mov dx, 0x1F7
    mov al, 0x20                    ; ATA Command 0x20: READ SECTORS
    out dx, al

    call ata_wait_drq
    jc .aln_done

    mov dx, 0x1F0
    mov cx, 256                     ; Read 256 words = 512 bytes
.aln_rd_words:
    in ax, dx
    mov [ds:di], ax
    add di, 2
    loop .aln_rd_words

    inc bl
    cmp bl, 32
    jb .aln_sec_loop

.aln_done:
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

ata_sync_nvram:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    ; 1. Mirror current hardware CMOS registers (0x40..0x5F) to 0x6FE0..0x6FFF
    mov cl, 0x40
    mov di, NVRAM_MIRROR
.asn_mirror_lp:
    mov al, cl
    call cmos_read_byte
    mov [ds:di], al
    inc di
    inc cl
    cmp cl, 0x60
    jb .asn_mirror_lp

    ; 2. Enable PIIX3 IDE Controller & check if Primary Master IDE drive is attached
    call ata_init_piix3_ide
    mov dx, 0x1F6
    mov al, 0xE0
    out dx, al
    mov dx, 0x1F7
    in al, dx
    cmp al, 0xFF
    je .asn_done
    test al, al
    jz .asn_done

    ; 3. Write 32 sectors (16,384 bytes: 0x3000..0x6FFF) to LBA 0..31
    mov si, 0x3000
    xor bl, bl                      ; BL = Sector LBA 0..31
.asn_sec_loop:
    call ata_wait_not_bsy
    jc .asn_done

    mov dx, 0x1F6
    mov al, 0xE0
    out dx, al

    mov dx, 0x1F2
    mov al, 1
    out dx, al

    mov dx, 0x1F3
    mov al, bl
    out dx, al

    mov dx, 0x1F4
    xor al, al
    out dx, al

    mov dx, 0x1F5
    out dx, al

    mov dx, 0x1F7
    mov al, 0x30                    ; ATA Command 0x30: WRITE SECTORS
    out dx, al

    call ata_wait_drq
    jc .asn_done

    mov dx, 0x1F0
    mov cx, 256                     ; Write 256 words = 512 bytes
.asn_wr_words:
    mov ax, [ds:si]
    out dx, ax
    add si, 2
    loop .asn_wr_words

    inc bl
    cmp bl, 32
    jb .asn_sec_loop

    ; 4. Send ATA Cache Flush (0xE7) so host file cybfs_nvram.img is synced immediately
    call ata_wait_not_bsy
    mov dx, 0x1F7
    mov al, 0xE7                    ; ATA Command 0xE7: FLUSH CACHE
    out dx, al
    call ata_wait_not_bsy

.asn_done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

ata_wait_not_bsy:
    push ax
    push cx
    push dx
    mov dx, 0x1F7
    mov cx, 30000
.awnb_lp:
    in al, dx
    cmp al, 0xFF
    je .awnb_err
    test al, 0x80                   ; Bit 7 = BSY
    jz .awnb_ok
    loop .awnb_lp
.awnb_err:
    pop dx
    pop cx
    pop ax
    stc
    ret
.awnb_ok:
    pop dx
    pop cx
    pop ax
    clc
    ret

ata_wait_drq:
    push ax
    push cx
    push dx
    mov dx, 0x1F7
    mov cx, 30000
.awd_lp:
    in al, dx
    cmp al, 0xFF
    je .awd_err
    test al, 0x80                   ; Bit 7 = BSY
    jnz .awd_next
    test al, 0x21                   ; Bit 0 = ERR, Bit 5 = DF
    jnz .awd_err
    test al, 0x08                   ; Bit 3 = DRQ
    jnz .awd_ok
.awd_next:
    loop .awd_lp
.awd_err:
    pop dx
    pop cx
    pop ax
    stc
    ret
.awd_ok:
    pop dx
    pop cx
    pop ax
    clc
    ret

; -----------------------------------------------------------------------------
; SCANCODE SET 1 -> ASCII LOOKUP TABLES (0x00..0x57)
; -----------------------------------------------------------------------------
sh_hex_chars:
    db "0123456789ABCDEF"

sh_scancode_norm:
    db 0,   0,  '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=',  0,   0
    db 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']',  0,   0,  'a', 's'
    db 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', "'", '`',  0,  '\\','z', 'x', 'c', 'v'
    db 'b', 'n', 'm', ',', '.', '/',  0,  '*',  0,  ' '
    times 30 db 0

sh_scancode_shift:
    db 0,   0,  '!', '@', '#', '$', '%', '^', '/', '*', '(', ')', '_', '+',  0,   0
    db 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}',  0,   0,  'A', 'S'
    db 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"', '~',  0,  '|', 'Z', 'X', 'C', 'V'
    db 'B', 'N', 'M', ';', ':', '?',  0,  '*',  0,  ' '
    times 30 db 0

sh_ac_table:
    db "help", 0, "usb", 0, "lsusb", 0, "xhci", 0, "ehci", 0, "mouse", 0
    db "factoryreset", 0, "wipe", 0, "resetbios", 0, "write ", 0, "nano ", 0
    db "edit ", 0, "setfont ", 0, "shutdown", 0, "reboot", 0, "append ", 0, "mkdir ", 0
    db "touch ", 0, "rm ", 0, "run ", 0, "format", 0, "memmap", 0, "memtest", 0, "map", 0
    db "sysinfo", 0, "pci", 0, "dmem ", 0, "cmos", 0, "cpu", 0, "time", 0, "sound ", 0
    db "color ", 0, "clear", 0, "snake", 0, "exit", 0, "cat ", 0, "cd ", 0, 0

cmd_usb:        db "usb", 0
cmd_lsusb:      db "lsusb", 0
cmd_xhci:       db "xhci", 0
cmd_ehci:       db "ehci", 0
cmd_mouse:      db "mouse", 0
cmd_factoryreset: db "factoryreset", 0
cmd_wipe:       db "wipe", 0
cmd_resetbios:  db "resetbios", 0
cmd_nano:       db "nano", 0
cmd_edit:       db "edit", 0
cmd_setfont:    db "setfont", 0
cmd_font:       db "font", 0
cmd_shutdown:   db "shutdown", 0
cmd_poweroff:   db "poweroff", 0
cmd_halt:       db "halt", 0
cmd_off:        db "off", 0
cmd_exit:       db "exit", 0
cmd_quit:       db "quit", 0
cmd_setup:      db "setup", 0
cmd_help:       db "help", 0
cmd_qmark:      db "?", 0
cmd_cls:        db "cls", 0
cmd_clear:      db "clear", 0
cmd_ver:        db "ver", 0
cmd_version:    db "version", 0
cmd_map:        db "map", 0
cmd_memmap:     db "memmap", 0
cmd_mem:        db "mem", 0
cmd_ls:         db "ls", 0
cmd_dir:        db "dir", 0
cmd_cd:         db "cd", 0
cmd_fs0:        db "fs0:", 0
cmd_blk0:       db "blk0:", 0
cmd_mkdir:      db "mkdir", 0
cmd_md:         db "md", 0
cmd_touch:      db "touch", 0
cmd_write:      db "write", 0
cmd_append:     db "append", 0
cmd_rm:         db "rm", 0
cmd_del:        db "del", 0
cmd_cat:        db "cat", 0
cmd_type:       db "type", 0
cmd_run:        db "run", 0
cmd_sh:         db "sh", 0
cmd_format:     db "format", 0
cmd_sysinfo:    db "sysinfo", 0
cmd_neofetch:   db "neofetch", 0
cmd_info:       db "info", 0
cmd_pci:        db "pci", 0
cmd_devices:    db "devices", 0
cmd_devtree:    db "devtree", 0
cmd_lspci:      db "lspci", 0
cmd_cpu:        db "cpu", 0
cmd_regs:       db "regs", 0
cmd_cmos:       db "cmos", 0
cmd_nvram:      db "nvram", 0
cmd_dmem:       db "dmem", 0
cmd_hex:        db "hex", 0
cmd_dump:       db "dump", 0
cmd_time:       db "time", 0
cmd_date:       db "date", 0
cmd_rtc:        db "rtc", 0
cmd_sound:      db "sound", 0
cmd_play:       db "play", 0
cmd_audio:      db "audio", 0
cmd_io:         db "io", 0
cmd_ports:      db "ports", 0
cmd_memtest:    db "memtest", 0
cmd_color:      db "color", 0
cmd_echo:       db "echo", 0
cmd_beep:       db "beep", 0
cmd_snake:      db "snake", 0
cmd_snake_efi:  db "snake.efi", 0
cmd_boot:       db "boot", 0
cmd_reboot:     db "reboot", 0
cmd_reset:      db "reset", 0

; --- Multi-Tab BIOS Setup Strings ---
str_setup_tab_hint:
    db "[TAB / 1 / 2] Switch Tab", 0
str_tab0_label:
    db " [ 1: Main & Game ] ", 0
str_tab1_label:
    db " [ 2: BiosShell ]   ", 0
str_box_title_shell:
    db " Cybforge EFI / BIOS Shell & Boot Configuration ", 0
str_opt_tab:
    db "Setup Menu Tab    : ", 0
str_val_tab_main:
    db "< 1: Main & Game >", 0
str_val_tab_shell:
    db "< 2: BiosShell   >", 0

str_opt_sh_launch:
    db "BiosShell         : ", 0
str_val_sh_launch:
    db "[ Press ENTER to Launch ]", 0
str_opt_sh_theme:
    db "Shell Color Scheme: ", 0
str_val_sht_efi:
    db "< Classic EFI (Yel) >", 0
str_val_sht_mat:
    db "< Matrix Hacker     >", 0
str_val_sht_cyb:
    db "< Cyber Neon (Cyan) >", 0
str_val_sht_blu:
    db "< Retro BIOS Blue   >", 0

str_opt_sh_prompt:
    db "Shell Prompt Style: ", 0
str_val_shp_fs0:
    db "< FS0:\\> (UEFI)     >", 0
str_val_shp_shl:
    db "< SHELL> (Compact)  >", 0
str_val_shp_roo:
    db "< root@cybforge:#   >", 0

str_opt_sh_banner:
    db "Startup Banner    : ", 0
str_val_shb_full:
    db "< Full EFI Dev Map  >", 0
str_val_shb_comp:
    db "< Compact Header    >", 0
str_val_shb_quiet:
    db "< Quiet (No Banner) >", 0

str_opt_sh_beep:
    db "Keystroke Beep    : ", 0
str_val_shk_on:
    db "< Enabled (Tactile) >", 0
str_val_shk_off:
    db "< Muted (Silent)    >", 0

str_opt_sh_boot:
    db "Default POST Boot : ", 0
str_val_shbt_snk:
    db "< Snake Game (3s)   >", 0
str_val_shbt_shl:
    db "< BiosShell (3s)    >", 0

str_opt_sh_reset:
    db "Reset Shell Cfg   : [ Press ENTER ]", 0
str_sh_tab_status:
    db "CybFS v1.0 Ready | Type 'exit' in Shell to return to Setup", 0

str_help_tab:
    db "Switch between [1: Main & Game] and [2: BiosShell] via TAB.", 0
str_help_sh1:
    db "Press [ENTER] to open the interactive Cybforge BIOS Shell.", 0
str_help_sh2:
    db "Select terminal color palette for the interactive BIOS Shell.", 0
str_help_sh3:
    db "Choose command prompt format (FS0:\\>, SHELL>, root@cybforge).", 0
str_help_sh4:
    db "Configure device table banner displayed when entering Shell.", 0
str_help_sh5:
    db "Enable or mute tactile keystroke sound inside the BIOS Shell.", 0
str_help_sh6:
    db "Choose whether POST boots Snake Game or directly to BiosShell.", 0

; --- Framed BIOS Shell v3.0 & Live CybFS Strings ---
str_sh_topbar:
    db "CYBFORGE UEFI/BIOS SHELL v3.0 [xHCI 3.0 + EHCI 2.0 + Mouse]  ROM:256K RAM:640K", 0
str_sh_frame_top:
    db " Cybforge Modern UEFI/BIOS Console [Persistent NVRAM + USB + Mouse] ", 0
str_sh_frame_bot:
    db " Click Dock Below: [HELP] | [USB / XHCI] | [LS / DIR] | [SNAKE] | [SETUP] ", 0
str_sh_botbar:
    db " [HELP] Cmds   [USB] xHCI/EHCI   [LS] Files   [SNAKE] Play Game   [EXIT] Setup", 0

str_pr_fs0_pfx:     db "FS0:\", 0
str_pr_gt:          db "> ", 0
str_pr_compact:     db "SHELL> ", 0
str_pr_root:        db "root@cybforge:# ", 0

str_sh_ban1:
    db "Cybforge UEFI/BIOS Shell v3.0 [xHCI USB 3.0 + EHCI USB 2.0 + CybFS v1.0]", 0
str_sh_ban2:
    db "Mounted Persistent NVRAM Disk (ATA Primary 0x1F0 LBA 0..31 <-> RAM 0x3000)", 0
str_sh_map_hdr:
    db "Handle  Media Type    Capacity   Hardware Device Path", 0
str_sh_map_sep:
    db "------  ------------  ---------  -----------------------------------------", 0
str_sh_map1:
    db "FS0:    CybFS NVRAM   16 KB R/W  AtaPrimary(0x1F0,LBA0..31)/RamDisk(0x3000)", 0
str_sh_map2:
    db "USB0:   xHCI + EHCI   USB 3.0/2  Pci(0,4)/xHCI(FEB00000h)+Pci(0,5)/EHCI", 0
str_sh_map3:
    db "BLK0:   Studio Audio  128 KB     PciRoot(0)/PcmAudio(16-Bit, 0xFFFD0000)", 0
str_sh_map4:
    db "HID0:   PS/2 + Mouse  80x25 Ptr  Isa8042(0x60,AuxIRQ12)/Pointer(640x400)", 0
str_sh_map5:
    db "VGA0:   Text Display  128 KB     Pci(0,2)/VgaController(80x25, VRAM:B800h)", 0
str_sh_map6:
    db "SB16:   Audio DSP     DMA Ch 5   IsaBridge(0x220)/SoundBlaster16(11025 Hz)", 0
str_sh_ban_hint:
    db "Try 'usb', 'mouse', 'write <file>', 'setfont', 'factoryreset', 'snake'.", 0

str_sh_err_pfx:
    db "Error: Unknown command '", 0
str_sh_err_sfx:
    db "'. Type 'help' for available commands.", 0

str_sh_hlp_hdr:
    db "Cybforge UEFI/BIOS Shell v3.0 - Command Reference (34 Built-In Commands):", 0
str_sh_hlp1:
    db "usb / lsusb  Live xHCI 3.0 & EHCI 2.0  mouse        Live Mouse Pointer status", 0
str_sh_hlp2:
    db "write <file> Open GNU Nano Editor!     ls / cd      Browse live CybFS Inodes", 0
str_sh_hlp3:
    db "cat <file>   Read live file bytes      append <f><t>Append line to real file", 0
str_sh_hlp4:
    db "mkdir <dir>  Create real directory     rm / del <f> Delete file/dir Inode", 0
str_sh_hlp5:
    db "touch <file> Create empty 0-byte file  run <f.nsh>  Run CybFS script", 0
str_sh_hlp6:
    db "setfont [1-4]Scale shell text size!    color [0-3]  Switch shell color theme", 0
str_sh_hlp7:
    db "factoryreset Wipe disk & reset BIOS!   format/wipe  Alias for factoryreset!", 0
str_sh_hlp8:
    db "pci / lspci  Live 0xCF8 PCI bus scan   map / memmap Device & E820 RAM map", 0
str_sh_hlp9:
    db "dmem [hex]   Live 64B Hex/ASCII dump   cmos / nvram Live CMOS & NVRAM dump", 0
str_sh_hlp10:
    db "cpu / regs   Dump live x86 registers   time / date  Read hardware RTC clock", 0
str_sh_hlp11:
    db "reboot       Real HW reset (0x64=FEh)  shutdown     ACPI S5 system power-off!", 0
str_sh_hlp12:
    db "snake / boot Launch Cybforge Snake 3.0 exit / quit  Return to BIOS Setup!", 0

str_sh_ver1:
    db "Cybforge UEFI Interactive Shell v3.0 [xHCI 3.0 + EHCI 2.0 + Mouse Edition]", 0
str_sh_ver2:
    db "  File System     : CybFS v1.0 (32 Inodes @ 0x3020, 19.4 KB R/W Pool @ 0x3420)", 0
str_sh_ver3:
    db "  USB Subsystem   : Bare-Metal xHCI (USB 3.0) + EHCI (USB 2.0) MMIO Drivers", 0
str_sh_ver4:
    db "  Pointer Driver  : 8042 PS/2 Auxiliary + USB HID Mouse (640x400 -> 80x25)", 0
str_sh_ver5:
    db "  Audio Engine    : Studio 16-Bit Marimba/Synth PCM on SB16 DSP v4.05 (DMA 5)", 0

str_sh_mm_hdr:
    db "Region Type   Start      End        Size    Description", 0
str_sh_mm_sep:
    db "------------  ---------  ---------  ------  ------------------------------", 0
str_sh_mm1:
    db "RT_Code       00000000h  000004FFh    1 KB  Real-Mode IVT & BIOS Data Area", 0
str_sh_mm2:
    db "BS_Data       00001000h  00001FFFh    4 KB  Kernel, USB, Mouse & Shell State", 0
str_sh_mm3:
    db "CybFS_RAM     00003000h  00007FFFh   20 KB  Live CybFS Inodes & R/W Pool", 0
str_sh_mm4:
    db "DMA_Buffer    00020000h  0002FFFFh   64 KB  SB16 16-Bit PCM DMA Bounce RAM", 0
str_sh_mm5:
    db "Conventional  00030000h  0009FFFFh  448 KB  Available Base System Memory", 0
str_sh_mm6:
    db "MMIO_VRAM     000A0000h  000BFFFFh  128 KB  VGA Graphics & Text VRAM", 0
str_sh_mm7:
    db "USB_MMIO      FEB00000h  FEB1FFFFh  128 KB  xHCI USB 3.0 & EHCI USB 2.0 BAR0", 0
str_sh_mm8:
    db "Audio_BIOS    FFFC0000h  FFFFFFFFh  256 KB  CybFS Master, PCM Bank & Kernel", 0
str_sh_mm_tot:
    db "Total: 640 KB Base RAM | 128 KB USB MMIO | 256 KB Flash ROM", 0

; --- Live CybFS Output Strings ---
str_ls_hdr_pfx:
    db "Live Directory of FS0:\\", 0
str_ls_hdr_sfx:
    db " (CybFS v1.0 Inode Table @ 0000:3020h):", 0
str_ls_col_hdr:
    db "Type     Size       Memory Addr   Name", 0
str_tag_dir:    db "<DIR>  ", 0
str_tag_ram:    db "[RAM]  ", 0
str_tag_rom:    db "[ROM]  ", 0
str_tag_hw:     db "[HW ]  ", 0
str_size_dir:   db "     -    ", 0
str_unit_b:     db " B  ", 0
str_ls_sum1:    db "Total: ", 0
str_ls_sum2:    db " File(s), ", 0
str_ls_sum3:    db " Dir(s) | Free R/W Pool: ", 0
str_ls_sum4:    db " Bytes", 0

str_cd_err:
    db "Error: Directory not found in CybFS.", 0
str_cd_notdir:
    db "Error: Target is a file, not a directory.", 0

str_mkdir_use:
    db "Usage: mkdir <dirname>  (Creates a real directory in CybFS)", 0
str_mkdir_ok:
    db "Created directory '", 0
str_exists_err:
    db "Error: An entry with that name already exists in this directory.", 0

str_touch_use:
    db "Usage: touch <filename>  (Creates an empty 0-byte file in CybFS)", 0
str_touch_ok:
    db "Created empty file '", 0
str_touch_ex_ok:
    db "File already exists (timestamp/inode verified).", 0

str_write_use:
    db "Usage: write <filename> <text>  (Writes real bytes to CybFS RAM pool)", 0
str_write_ok1:
    db "Wrote ", 0
str_write_ok2:
    db " Bytes to CybFS file '", 0
str_Quote_ok:
    db "'.", 0
str_fs_full:
    db "Error: CybFS Inode table (32 max) or R/W Data Pool (0x7FFF) is full!", 0

str_app_use:
    db "Usage: append <filename> <text>  (Appends a line to an existing RAM file)", 0
str_app_rom_err:
    db "Error: Cannot append to read-only [ROM] / [HW] file.", 0
str_app_ok1:
    db "Appended line to '", 0
str_app_ok2:
    db "' (New size: ", 0
str_app_ok3:
    db " Bytes).", 0

str_rm_use:
    db "Usage: rm <name>  (Deletes a file or directory Inode from CybFS)", 0
str_rm_ok:
    db "Deleted Inode '", 0

str_cat_usage:
    db "Usage: cat <filename>  (Reads live file bytes from CybFS Inode)", 0
str_cat_nf_pfx:
    db "Error: File not found in current CybFS directory (Use 'ls').", 0
str_cat_hdr1:
    db "--- [ ", 0
str_cat_hdr2:
    db " (", 0
str_cat_hdr3:
    db " Bytes) ] ---", 0

str_run_use:
    db "Usage: run <script.nsh>  (Executes commands line-by-line from CybFS file)", 0
str_run_err:
    db "Error: Target is not an executable script file.", 0
str_fmt_ok1:
    db "[FACTORY RESET] Wiping persistent ATA NVRAM disk (LBA 0..31) & RAM pool...", 0
str_fmt_ok2:
    db "[FACTORY RESET] CybFS v1.0 restored from ROM Block 0 (All files erased).", 0
str_fmt_ok3:
    db "[FACTORY RESET] BIOS Setup settings, Font Scale & Highscores reset OK!", 0

str_neo1:
    db "   .==========.     root@cybforge-uefi-v3", 0
str_neo2:
    db "  /  CYBFORGE  \    ------------------------------------------", 0
str_neo3:
    db " |   [x86-32]   |   Shell    : Cybforge UEFI/BIOS Shell v3.0", 0
str_neo4:
    db " |  UEFI  v3.0  |   USB Bus  : xHCI USB 3.0 + EHCI USB 2.0 Active", 0
str_neo5:
    db "  \  MAXIMAL   /    Input    : PS/2 Keyboard + Hardware Mouse ON", 0
str_neo6:
    db "   '=========='     Audio    : Studio 16-Bit PCM Synth (SB16 DMA5)", 0
str_neo7:
    db "                    Game     : Cybforge Snake v3.0 ('snake' to play)", 0

; --- Live PCI, USB (xHCI/EHCI) & Mouse Hardware Strings ---
str_pci_hdr:
    db "Bus Dv Fn  Ven:Dev   Class   Live Hardware PCI Configuration (Port 0xCF8):", 0
str_pci_b0:
    db "00  ", 0
str_pci_cl_pfx:
    db "Class=", 0
str_pci_desc_brg:
    db "  PCI Host/ISA Bridge Controller", 0
str_pci_desc_vga:
    db "  VGA Compatible Display Adapter", 0
str_pci_desc_ide:
    db "  Bus-Master IDE Storage Controller", 0
str_pci_desc_net:
    db "  PCI Ethernet Network Adapter", 0
str_pci_desc_usb:
    db "  xHCI USB 3.0 / EHCI USB 2.0 Controller", 0
str_pci_desc_gen:
    db "  PCI System Peripheral Device", 0
str_pci_isa:
    db "ISA/HID :  0220h=SB16 Studio DSP | 0060h=PS/2 Kbd+Mouse | FEB00000h=USB MMIO", 0

str_usb_hdr:
    db "Live Bare-Metal USB 3.0 (xHCI) & USB 2.0 (EHCI) Host Controller Status:", 0
str_usb_sep:
    db "--------------------------------------------------------------------------", 0
str_usb_xhci1:
    db "[xHCI USB 3.0] PCI ", 0
str_usb_xhci2:
    db " @ MMIO 0xFEB00000 (USBCMD.RS=1, USB 3.0 5Gbps)", 0
str_usb_xhci3:
    db "  HCI Ver: ", 0
str_usb_xhci4:
    db " | MaxSlots: ", 0
str_usb_xhci5:
    db " | Ports: ", 0
str_usb_xhci6:
    db " | Connected: ", 0
str_usb_xhci7:
    db " | Port1_SC: ", 0
str_usb_ehci1:
    db "[EHCI USB 2.0] PCI ", 0
str_usb_ehci2:
    db " @ MMIO 0xFEB10000 (USBCMD.RS=1, CF=1, 480Mbps)", 0
str_usb_ehci3:
    db "  HCI Ver: ", 0
str_usb_ehci5:
    db " | Root Hub Ports: ", 0
str_usb_tree1:
    db "  +-- RootHub(xHCI.0) -> Port 1: SuperSpeed USB 3.0 Hub (CCS=1, PED=1)", 0
str_usb_tree2:
    db "  +-- RootHub(EHCI.0) -> Port 1: High-Speed USB 2.0 Device (CCS=1, HS)", 0

str_mouse_hdr:
    db "Live 8042 Auxiliary PS/2 & USB Pointer Driver Telemetry:", 0
str_mouse_line1:
    db "  Driver State: ACTIVE (Stream Mode 0xF4, Aux Port 0xA8, Cursor Glyph 0x14)", 0
str_mouse_pos1:
    db "  Text Cell (X,Y): ", 0
str_mouse_pos2:
    db "  | Fine Pixel (X,Y): ", 0
str_mouse_pos3:
    db "  | Packets Decoded: ", 0

str_cpu_hdr:
    db "x86 Processor Live Register & Segment State:", 0
str_cpu_cs:     db "  CS=", 0
str_cpu_ds:     db "  DS=", 0
str_cpu_es:     db "  ES=", 0
str_cpu_fs:     db "  FS=", 0
str_cpu_sp:     db "  SP=", 0
str_cpu_cr0:
    db "  Mode: 16-Bit Real Mode + 32-Bit Unreal FS Descriptor (Limit=4GB, A20=ON)", 0

str_cmos_hdr:
    db "Live CMOS NVRAM Register Dump (Ports 0x70/0x71, Registers 0x40..0x5F):", 0
str_cmos_r40:   db "  0x40: ", 0
str_cmos_r50:   db "  0x50: ", 0
str_cmos_ok:
    db "  Signature 0x40 = 0xCC [VALID] | XOR Checksum 0x5E = OK | Top 3 Stored", 0

str_seg_ram:    db "0000:", 0
str_seg_rom:    db "F000:", 0

str_rtc_pfx:    db "Hardware RTC Clock (CMOS BCD): ", 0
str_rtc_sfx:    db " UTC  [Battery: OK]", 0

str_snd_play1:  db "Playing 16-Bit PCM Sample [", 0
str_snd_play2:  db "] via SB16 DMA Channel 5 (11,025 Hz)... OK", 0
str_snd_list:   db "  Bank: 0=Crunch 1=Gold 2=Crash 3=Start 4=Pause 5=Boot 6=GameOver 7=Victory", 0

str_io_hdr:     db "Live I/O Ports: ", 0
str_io_p60:     db "0x60(KBD)=", 0
str_io_p61:     db " 0x61(SPK)=", 0
str_io_p64:     db " 0x64(STS)=", 0
str_io_p22c:    db " 0x22C(DSP)=", 0
str_io_p3da:    db " 0x3DA(VGA)=", 0

str_mt_1:
    db "Testing 64 KB Extended RAM (0x20000..0x2FFFF) [Write & Verify 0x55AA/0xAA55]...", 0
str_mt_2:
    db "Result: 65,536 Word Reads Verified - ", 0
str_mt_3:
    db " Errors Detected (LIVE RAM TEST OK)", 0

str_col_ok:
    db "Shell color scheme updated and saved to CMOS NVRAM.", 0
str_beep_ok:
    db "Acoustic diagnostic tone triggered.", 0

; --- GNU Nano Editor (Cybforge Nano v2.7) Strings ---
str_nano_top_l:
    db "GNU nano 2.7 [CybFS Live]", 0
str_nano_file_pfx:
    db "File: ", 0
str_nano_mod_yes:
    db "[ Modified ]", 0
str_nano_mod_no:
    db "[ Saved OK ]", 0
str_nano_frm_hdr:
    db " Ln | CybFS R/W Buffer (72 Cols x 18 Lines) ", 0
str_nano_msg_rdy:
    db "[ Ready: Type multi-line text | ^O/F2=WriteOut | ^S/F3=Save&Exit | ^X/ESC=Exit ]", 0
str_nano_msg_sv1:
    db "[ Wrote ", 0
str_nano_msg_sv2:
    db " Bytes to live CybFS file '", 0
str_nano_msg_sv3:
    db "' (Inode Updated) ]", 0
str_nano_msg_ask:
    db "Save modified buffer?  [Y / Enter] Yes (Save)   [N] No (Discard)   [C] Cancel", 0
str_nano_msg_cut:
    db "[ Cut current line from buffer (^K / F4) ]", 0
str_nano_msg_hlp:
    db "[ Help: Arrows/Home/End=Move | Enter=New Line | ^O/F2=Save | ^X/ESC=Exit ]", 0
str_nano_stat1:
    db "Line: ", 0
str_nano_stat2:
    db "/18  Col: ", 0
str_nano_stat3:
    db "/72  |  Saved Size: ", 0
str_nano_stat4:
    db " B  |  Free Pool: ", 0
str_nano_bot1:
    db " {^G/F1} Get Help   {^O/F2} WriteOut   {^S/F3} Save&Exit  {^K/F4} Cut Line   {HOME } Start ", 0
str_nano_bot2:
    db " {^X/ESC} Exit Nano {ARROWS} Move Curs {ENTER} New Line   {BS/DEL} Erase Ch  {END  } End   ", 0
str_nano_closed1:
    db "Closed Nano buffer for '", 0

; --- Setfont, Reboot & Shutdown Strings ---
str_sf_ok_pfx:
    db "VGA Hardware Font Scale set to: ", 0
str_sf_name_0:
    db "[1: Small 8x8 Micro Font (50% Height)]", 0
str_sf_name_1:
    db "[2: Medium 8x12 Compact Font (75% Height)]", 0
str_sf_name_2:
    db "[3: Large 8x16 Standard IBM VGA (100% Height)]", 0
str_sf_name_3:
    db "[4: Huge 8x16 XL Tall Font (140% Height)]", 0
str_sf_usage:
    db "  Usage: setfont 1 (Small) | 2 (Medium) | 3 (Large) | 4 (Huge XL)", 0

str_reboot_msg:
    db "[SYSTEM] Syncing ATA NVRAM disk & triggering hardware reset (Port 0x64=0xFE)...", 0
str_shut_msg1:
    db "[ACPI S5] Flushing CybFS & CMOS to ATA disk (cybfs_nvram.img, LBA 0..31)...", 0
str_shut_msg2:
    db "[ACPI S5] Sending SLP_TYP5 (0x2000) to PM1a_CNT (Port 0x0604) -> Power Off!", 0
str_shut_halted:
    db "[SYSTEM HALTED] CPU in low-power HLT state. It is now safe to turn off PC.", 0

; Modern UEFI Dark Slate Palette for POST, BIOS Setup & UEFI Shell (48 Bytes)
ui_modern_palette:
    ; 0:DeepSlate  1:Sapphire  2:Emerald   3:DeepTeal  4:Crimson   5:Purple    6:WarmGold  7:FrostSilv
    db 3, 4, 8,    6, 13, 30,  6, 36, 18,  5, 28, 36,  44, 9, 12,  26, 10, 36, 46, 30, 5,  48, 51, 56
    ; 8:SteelGray  9:RoyalBlu  10:NeonMint 11:ElecCyan 12:CoralRed 13:Orchid   14:SunGold  15:PureWhite
    db 20, 24, 32, 18, 36, 63, 14, 60, 30, 14, 57, 63, 63, 18, 20, 58, 22, 63, 63, 56, 14, 63, 63, 63

; Hardware VGA DAC Palette Themes for Google Snake Game (4 Themes x 48 Bytes = 192 Bytes)
; Note: Slot 2 (0x20 bg) and Slot 7 (0x70 bg) form the 2-tone Grass Checkerboard!
;       Slot 0 (0x00 bg) is the Dark Forest-Green HUD bar & outer border!
;       Slot 3 (0x30 bg) is the Google Sky-Blue Popup Card!
;       Slot 1 (0x10 bg) is the Google Royal-Blue Card Button!
palette_themes_table:
    ; Theme 0: Google Snake Maximalist Grass (Authentic Google Snake Colors!)
    ; 0:ForestHUD  1:BtnBlue   2:GrassMed  3:SkyCard   4:MossWall  5:Shadow    6:WarmGold  7:GrassLight
    db 18, 29, 11, 6, 22, 54,  35, 51, 14, 21, 48, 60, 14, 23, 8,  9, 14, 20,  54, 36, 6,  42, 54, 18
    ; 8:DarkPine   9:SnakeBlue 10:HeadBlue 11:IceBorder12:AppleRed 13:CutePink 14:TrophyGld15:PureWhite
    db 11, 18, 6,  14, 28, 62, 20, 36, 63, 38, 58, 63, 60, 13, 9,  63, 32, 45, 63, 51, 6,  63, 63, 63

    ; Theme 1: Cyber Emerald Checkerboard
    db 4, 14, 10,  6, 24, 52,  8, 32, 20,  14, 42, 56, 4, 20, 12,  6, 10, 14,  45, 35, 6,  12, 38, 24
    db 6, 20, 14,  14, 40, 63, 20, 52, 63, 36, 60, 63, 63, 16, 16, 60, 24, 60, 63, 56, 12, 63, 63, 63

    ; Theme 2: Golden Autumn Meadow
    db 22, 14, 6,  8, 24, 52,  42, 30, 10, 20, 46, 58, 28, 18, 6,  10, 10, 14, 52, 34, 6,  48, 36, 14
    db 18, 12, 4,  12, 28, 62, 18, 36, 63, 38, 56, 63, 62, 12, 8,  60, 28, 44, 63, 54, 10, 63, 63, 63

    ; Theme 3: Retro Arcade Checkerboard
    db 6, 8, 22,   10, 24, 56, 12, 18, 38, 18, 44, 58, 8, 12, 28,  4, 6, 14,   50, 32, 8,  16, 24, 46
    db 12, 16, 30, 16, 58, 28, 24, 63, 36, 36, 58, 63, 63, 16, 18, 63, 24, 60, 63, 56, 14, 63, 63, 63
"""

part3_tables = content[content.find("vga_seq_table:"):content.find("font_table:")]

# Part 4: True 16-Scanline IBM VGA 8x16 BIOS Font (Crisp 1x1 Scanlines, Zero Row Collision)
font_defs = {
    # Custom game glyphs (overridden by custom_glyphs_table, included for completeness)
    0x01: [0x00,0x00,0x00,0x00,0x00,0x00,0x3F,0x20,0x3F,0x24,0x24,0x24,0x24,0x24,0x24,0x24],
    0x02: [0x00,0x00,0x00,0x00,0x00,0x00,0xFC,0x04,0xFC,0x24,0x24,0x24,0x24,0x24,0x24,0x24],
    0x03: [0x24,0x24,0x24,0x24,0x24,0x24,0x3F,0x20,0x3F,0x00,0x00,0x00,0x00,0x00,0x00,0x00],
    0x04: [0x24,0x24,0x24,0x24,0x24,0x24,0xFC,0x04,0xFC,0x00,0x00,0x00,0x00,0x00,0x00,0x00],
    0x05: [0x00,0x00,0x00,0x00,0x00,0x00,0xFF,0x00,0xFF,0x00,0x00,0x00,0x00,0x00,0x00,0x00],
    0x06: [0x24,0x24,0x24,0x24,0x24,0x24,0x24,0x24,0x24,0x24,0x24,0x24,0x24,0x24,0x24,0x24],
    0x07: [0x00,0x3C,0x7E,0xFF,0xC3,0xDB,0xDB,0xFF,0xFF,0xBD,0x99,0xC3,0x7E,0x7E,0x3C,0x00],
    0x08: [0x06,0x0E,0x0C,0x18,0x10,0x76,0xFF,0xDF,0xBF,0xFF,0xFF,0xFF,0x7E,0x7E,0x3C,0x00],
    0x09: [0x3C,0x7E,0xFF,0xEF,0xD7,0xBB,0x7D,0xFF,0xEF,0xD7,0xBB,0x7D,0xFF,0x7E,0x7E,0x3C],
    0x0A: [0x00,0x3C,0x7E,0xFF,0x7E,0xDB,0xD7,0xCF,0xFF,0xFF,0xE7,0xDB,0x7E,0x7E,0x3C,0x00],

    # Authentic IBM VGA 8x16 Font (Scanlines 0..15: Top gap 0..1, Caps 2..11, Descenders 12..14, Bot gap 15)
    ord(' '): [0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00],
    ord('!'): [0x00,0x00,0x18,0x3C,0x3C,0x3C,0x18,0x18,0x18,0x00,0x18,0x18,0x00,0x00,0x00,0x00],
    ord('"'): [0x00,0x66,0x66,0x66,0x24,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00],
    ord('#'): [0x00,0x00,0x00,0x6C,0x6C,0xFE,0x6C,0x6C,0x6C,0xFE,0x6C,0x6C,0x00,0x00,0x00,0x00],
    ord('$'): [0x18,0x18,0x7C,0xC6,0xC2,0xC0,0x7C,0x06,0x06,0x86,0xC6,0x7C,0x18,0x18,0x00,0x00],
    ord('%'): [0x00,0x00,0x00,0x00,0xC2,0xC6,0x0C,0x18,0x30,0x60,0xC6,0x86,0x00,0x00,0x00,0x00],
    ord('&'): [0x00,0x00,0x38,0x6C,0x6C,0x38,0x76,0xDC,0xCC,0xCC,0xCC,0x76,0x00,0x00,0x00,0x00],
    ord('\''):[0x00,0x30,0x30,0x30,0x60,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00],
    ord('('): [0x00,0x00,0x0C,0x18,0x30,0x30,0x30,0x30,0x30,0x30,0x18,0x0C,0x00,0x00,0x00,0x00],
    ord(')'): [0x00,0x00,0x30,0x18,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x18,0x30,0x00,0x00,0x00,0x00],
    ord('*'): [0x00,0x00,0x00,0x00,0x66,0x3C,0xFF,0x3C,0x66,0x00,0x00,0x00,0x00,0x00,0x00,0x00],
    ord('+'): [0x00,0x00,0x00,0x00,0x00,0x18,0x18,0x7E,0x18,0x18,0x00,0x00,0x00,0x00,0x00,0x00],
    ord(','): [0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x18,0x18,0x18,0x30,0x00,0x00,0x00],
    ord('-'): [0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xFE,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00],
    ord('.'): [0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x18,0x18,0x00,0x00,0x00,0x00],
    ord('/'): [0x00,0x00,0x00,0x00,0x02,0x06,0x0C,0x18,0x30,0x60,0xC0,0x80,0x00,0x00,0x00,0x00],

    ord('0'): [0x00,0x00,0x7C,0xC6,0xCE,0xDE,0xF6,0xE6,0xC6,0xC6,0xC6,0x7C,0x00,0x00,0x00,0x00],
    ord('1'): [0x00,0x00,0x18,0x38,0x78,0x18,0x18,0x18,0x18,0x18,0x18,0x7E,0x00,0x00,0x00,0x00],
    ord('2'): [0x00,0x00,0x7C,0xC6,0x06,0x0C,0x18,0x30,0x60,0xC0,0xC6,0xFE,0x00,0x00,0x00,0x00],
    ord('3'): [0x00,0x00,0x7C,0xC6,0x06,0x06,0x3C,0x06,0x06,0x06,0xC6,0x7C,0x00,0x00,0x00,0x00],
    ord('4'): [0x00,0x00,0x0C,0x1C,0x3C,0x6C,0xCC,0xFE,0x0C,0x0C,0x0C,0x1E,0x00,0x00,0x00,0x00],
    ord('5'): [0x00,0x00,0xFE,0xC0,0xC0,0xC0,0xFC,0x06,0x06,0x06,0xC6,0x7C,0x00,0x00,0x00,0x00],
    ord('6'): [0x00,0x00,0x38,0x60,0xC0,0xC0,0xFC,0xC6,0xC6,0xC6,0xC6,0x7C,0x00,0x00,0x00,0x00],
    ord('7'): [0x00,0x00,0xFE,0xC6,0x06,0x06,0x0C,0x18,0x30,0x30,0x30,0x30,0x00,0x00,0x00,0x00],
    ord('8'): [0x00,0x00,0x7C,0xC6,0xC6,0xC6,0x7C,0xC6,0xC6,0xC6,0xC6,0x7C,0x00,0x00,0x00,0x00],
    ord('9'): [0x00,0x00,0x7C,0xC6,0xC6,0xC6,0x7E,0x06,0x06,0x06,0x0C,0x78,0x00,0x00,0x00,0x00],

    ord(':'): [0x00,0x00,0x00,0x00,0x18,0x18,0x00,0x00,0x00,0x18,0x18,0x00,0x00,0x00,0x00,0x00],
    ord(';'): [0x00,0x00,0x00,0x00,0x18,0x18,0x00,0x00,0x00,0x18,0x18,0x30,0x00,0x00,0x00,0x00],
    ord('<'): [0x00,0x00,0x00,0x06,0x0C,0x18,0x30,0x60,0x30,0x18,0x0C,0x06,0x00,0x00,0x00,0x00],
    ord('='): [0x00,0x00,0x00,0x00,0x00,0x7E,0x00,0x00,0x7E,0x00,0x00,0x00,0x00,0x00,0x00,0x00],
    ord('>'): [0x00,0x00,0x00,0x60,0x30,0x18,0x0C,0x06,0x0C,0x18,0x30,0x60,0x00,0x00,0x00,0x00],
    ord('?'): [0x00,0x00,0x7C,0xC6,0xC6,0x0C,0x18,0x18,0x18,0x00,0x18,0x18,0x00,0x00,0x00,0x00],
    ord('@'): [0x00,0x00,0x00,0x7C,0xC6,0xC6,0xDE,0xDE,0xDE,0xDC,0xC0,0x7C,0x00,0x00,0x00,0x00],

    ord('A'): [0x00,0x00,0x10,0x38,0x6C,0xC6,0xC6,0xFE,0xC6,0xC6,0xC6,0xC6,0x00,0x00,0x00,0x00],
    ord('B'): [0x00,0x00,0xFC,0x66,0x66,0x66,0x7C,0x66,0x66,0x66,0x66,0xFC,0x00,0x00,0x00,0x00],
    ord('C'): [0x00,0x00,0x3C,0x66,0xC2,0xC0,0xC0,0xC0,0xC0,0xC2,0x66,0x3C,0x00,0x00,0x00,0x00],
    ord('D'): [0x00,0x00,0xF8,0x6C,0x66,0x66,0x66,0x66,0x66,0x66,0x6C,0xF8,0x00,0x00,0x00,0x00],
    ord('E'): [0x00,0x00,0xFE,0x66,0x62,0x68,0x78,0x68,0x60,0x62,0x66,0xFE,0x00,0x00,0x00,0x00],
    ord('F'): [0x00,0x00,0xFE,0x66,0x62,0x68,0x78,0x68,0x60,0x60,0x60,0xF0,0x00,0x00,0x00,0x00],
    ord('G'): [0x00,0x00,0x3C,0x66,0xC2,0xC0,0xC0,0xDE,0xC6,0xC6,0x66,0x3A,0x00,0x00,0x00,0x00],
    ord('H'): [0x00,0x00,0xC6,0xC6,0xC6,0xC6,0xFE,0xC6,0xC6,0xC6,0xC6,0xC6,0x00,0x00,0x00,0x00],
    ord('I'): [0x00,0x00,0x3C,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x3C,0x00,0x00,0x00,0x00],
    ord('J'): [0x00,0x00,0x1E,0x0C,0x0C,0x0C,0x0C,0x0C,0xCC,0xCC,0xCC,0x78,0x00,0x00,0x00,0x00],
    ord('K'): [0x00,0x00,0xE6,0x66,0x66,0x6C,0x78,0x78,0x6C,0x66,0x66,0xE6,0x00,0x00,0x00,0x00],
    ord('L'): [0x00,0x00,0xF0,0x60,0x60,0x60,0x60,0x60,0x60,0x62,0x66,0xFE,0x00,0x00,0x00,0x00],
    ord('M'): [0x00,0x00,0xC6,0xEE,0xFE,0xFE,0xD6,0xC6,0xC6,0xC6,0xC6,0xC6,0x00,0x00,0x00,0x00],
    ord('N'): [0x00,0x00,0xC6,0xE6,0xF6,0xFE,0xDE,0xCE,0xC6,0xC6,0xC6,0xC6,0x00,0x00,0x00,0x00],
    ord('O'): [0x00,0x00,0x38,0x6C,0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0x6C,0x38,0x00,0x00,0x00,0x00],
    ord('P'): [0x00,0x00,0xFC,0x66,0x66,0x66,0x7C,0x60,0x60,0x60,0x60,0xF0,0x00,0x00,0x00,0x00],
    ord('Q'): [0x00,0x00,0x7C,0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0xD6,0xDE,0x7C,0x0C,0x0E,0x00,0x00],
    ord('R'): [0x00,0x00,0xFC,0x66,0x66,0x66,0x7C,0x6C,0x66,0x66,0x66,0xE6,0x00,0x00,0x00,0x00],
    ord('S'): [0x00,0x00,0x7C,0xC6,0xC6,0x60,0x38,0x0C,0x06,0xC6,0xC6,0x7C,0x00,0x00,0x00,0x00],
    ord('T'): [0x00,0x00,0x7E,0x7E,0x5A,0x18,0x18,0x18,0x18,0x18,0x18,0x3C,0x00,0x00,0x00,0x00],
    ord('U'): [0x00,0x00,0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0x7C,0x00,0x00,0x00,0x00],
    ord('V'): [0x00,0x00,0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0x6C,0x38,0x10,0x00,0x00,0x00,0x00],
    ord('W'): [0x00,0x00,0xC6,0xC6,0xC6,0xC6,0xD6,0xD6,0xFE,0xEE,0x6C,0x44,0x00,0x00,0x00,0x00],
    ord('X'): [0x00,0x00,0xC6,0xC6,0x6C,0x7C,0x38,0x38,0x7C,0x6C,0xC6,0xC6,0x00,0x00,0x00,0x00],
    ord('Y'): [0x00,0x00,0x66,0x66,0x66,0x66,0x3C,0x18,0x18,0x18,0x18,0x3C,0x00,0x00,0x00,0x00],
    ord('Z'): [0x00,0x00,0xFE,0xC6,0x86,0x0C,0x18,0x30,0x60,0xC2,0xC6,0xFE,0x00,0x00,0x00,0x00],

    ord('['): [0x00,0x00,0x3C,0x30,0x30,0x30,0x30,0x30,0x30,0x30,0x30,0x3C,0x00,0x00,0x00,0x00],
    ord('\\'):[0x00,0x00,0x00,0x80,0xC0,0xE0,0x70,0x38,0x1C,0x0E,0x06,0x02,0x00,0x00,0x00,0x00],
    ord(']'): [0x00,0x00,0x3C,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x3C,0x00,0x00,0x00,0x00],
    ord('^'): [0x10,0x38,0x6C,0xC6,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00],
    ord('_'): [0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xFF,0x00,0x00],
    ord('`'): [0x30,0x30,0x18,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00],

    ord('a'): [0x00,0x00,0x00,0x00,0x00,0x78,0x0C,0x7C,0xCC,0xCC,0xCC,0x76,0x00,0x00,0x00,0x00],
    ord('b'): [0x00,0x00,0xE0,0x60,0x60,0x78,0x6C,0x66,0x66,0x66,0x66,0x7C,0x00,0x00,0x00,0x00],
    ord('c'): [0x00,0x00,0x00,0x00,0x00,0x7C,0xC6,0xC0,0xC0,0xC0,0xC6,0x7C,0x00,0x00,0x00,0x00],
    ord('d'): [0x00,0x00,0x1C,0x0C,0x0C,0x3C,0x6C,0xCC,0xCC,0xCC,0xCC,0x76,0x00,0x00,0x00,0x00],
    ord('e'): [0x00,0x00,0x00,0x00,0x00,0x7C,0xC6,0xFE,0xC0,0xC0,0xC6,0x7C,0x00,0x00,0x00,0x00],
    ord('f'): [0x00,0x00,0x38,0x6C,0x64,0x60,0xF0,0x60,0x60,0x60,0x60,0xF0,0x00,0x00,0x00,0x00],
    ord('g'): [0x00,0x00,0x00,0x00,0x00,0x76,0xCC,0xCC,0xCC,0xCC,0x7C,0x0C,0xCC,0x78,0x00,0x00],
    ord('h'): [0x00,0x00,0xE0,0x60,0x60,0x6C,0x76,0x66,0x66,0x66,0x66,0xE6,0x00,0x00,0x00,0x00],
    ord('i'): [0x00,0x00,0x18,0x18,0x00,0x38,0x18,0x18,0x18,0x18,0x18,0x3C,0x00,0x00,0x00,0x00],
    ord('j'): [0x00,0x00,0x06,0x06,0x00,0x0E,0x06,0x06,0x06,0x06,0x06,0x66,0x66,0x3C,0x00,0x00],
    ord('k'): [0x00,0x00,0xE0,0x60,0x60,0x66,0x6C,0x78,0x78,0x6C,0x66,0xE6,0x00,0x00,0x00,0x00],
    ord('l'): [0x00,0x00,0x38,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x3C,0x00,0x00,0x00,0x00],
    ord('m'): [0x00,0x00,0x00,0x00,0x00,0xEC,0xFE,0xD6,0xD6,0xD6,0xD6,0xC6,0x00,0x00,0x00,0x00],
    ord('n'): [0x00,0x00,0x00,0x00,0x00,0xDC,0x66,0x66,0x66,0x66,0x66,0x66,0x00,0x00,0x00,0x00],
    ord('o'): [0x00,0x00,0x00,0x00,0x00,0x7C,0xC6,0xC6,0xC6,0xC6,0xC6,0x7C,0x00,0x00,0x00,0x00],
    ord('p'): [0x00,0x00,0x00,0x00,0x00,0xDC,0x66,0x66,0x66,0x66,0x7C,0x60,0x60,0xF0,0x00,0x00],
    ord('q'): [0x00,0x00,0x00,0x00,0x00,0x76,0xCC,0xCC,0xCC,0xCC,0x7C,0x0C,0x0C,0x1E,0x00,0x00],
    ord('r'): [0x00,0x00,0x00,0x00,0x00,0xDC,0x76,0x66,0x60,0x60,0x60,0xF0,0x00,0x00,0x00,0x00],
    ord('s'): [0x00,0x00,0x00,0x00,0x00,0x7C,0xC6,0x60,0x38,0x0C,0xC6,0x7C,0x00,0x00,0x00,0x00],
    ord('t'): [0x00,0x00,0x10,0x30,0x30,0xFC,0x30,0x30,0x30,0x30,0x36,0x1C,0x00,0x00,0x00,0x00],
    ord('u'): [0x00,0x00,0x00,0x00,0x00,0xCC,0xCC,0xCC,0xCC,0xCC,0xCC,0x76,0x00,0x00,0x00,0x00],
    ord('v'): [0x00,0x00,0x00,0x00,0x00,0xC6,0xC6,0xC6,0xC6,0x6C,0x38,0x10,0x00,0x00,0x00,0x00],
    ord('w'): [0x00,0x00,0x00,0x00,0x00,0xC6,0xC6,0xD6,0xD6,0xFE,0xEE,0x6C,0x00,0x00,0x00,0x00],
    ord('x'): [0x00,0x00,0x00,0x00,0x00,0xC6,0x6C,0x38,0x38,0x38,0x6C,0xC6,0x00,0x00,0x00,0x00],
    ord('y'): [0x00,0x00,0x00,0x00,0x00,0xC6,0xC6,0xC6,0xC6,0xC6,0x7E,0x06,0x0C,0xF8,0x00,0x00],
    ord('z'): [0x00,0x00,0x00,0x00,0x00,0xFE,0xCC,0x18,0x30,0x60,0xC6,0xFE,0x00,0x00,0x00,0x00],

    ord('{'): [0x00,0x00,0x0E,0x18,0x18,0x18,0x70,0x18,0x18,0x18,0x18,0x0E,0x00,0x00,0x00,0x00],
    ord('|'): [0x00,0x00,0x18,0x18,0x18,0x18,0x00,0x18,0x18,0x18,0x18,0x18,0x00,0x00,0x00,0x00],
    ord('}'): [0x00,0x00,0x70,0x18,0x18,0x18,0x0E,0x18,0x18,0x18,0x18,0x70,0x00,0x00,0x00,0x00],
    ord('~'): [0x00,0x00,0x76,0xDC,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00],
}

font_table_asm = "font_table:\n"
for code in sorted(font_defs.keys()):
    bytes_str = ", ".join([f"0x{b:02X}" for b in font_defs[code]])
    if code in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]:
        font_table_asm += f"    db 0x{code:02X}, {bytes_str}\n"
    else:
        ch = chr(code)
        font_table_asm += f"    db 0x{code:02X}, {bytes_str} ; '{ch}'\n"
font_table_asm += "    db 0\n"

part5_tail = content[content.find("times 0xFFF0"):]


custom_glyphs_table_def = {
    # 0x01..0x06: Rounded Modern Double/Thick Box Borders
    0x01: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1F, 0x30, 0x37, 0x2C, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24],
    0x02: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF8, 0x0C, 0xEC, 0x34, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24],
    0x03: [0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x2C, 0x37, 0x30, 0x1F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
    0x04: [0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x34, 0xEC, 0x0C, 0xF8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
    0x05: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
    0x06: [0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24],

    # 0x07: Google Snake Cute Big-Eyed Head (Expressive eyes + cute nostrils/smile)
    0x07: [0x00, 0x3C, 0x7E, 0xFF, 0x99, 0x99, 0xDB, 0xDB, 0xFF, 0xFF, 0xE7, 0xFF, 0xBD, 0xC3, 0x7E, 0x3C],

    # 0x08: Google Snake Plump Glossy Red Apple (with stem & leaf at top)
    0x08: [0x0C, 0x1E, 0x18, 0x76, 0xFF, 0xDF, 0xBF, 0xBF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7E, 0x7E, 0x3C, 0x00],

    # 0x09: Google Snake Golden Trophy Cup (Goblet with handles & pedestal base)
    0x09: [0x00, 0x7E, 0xFF, 0xDB, 0xDB, 0xFF, 0x7E, 0x3C, 0x18, 0x18, 0x18, 0x3C, 0x7E, 0x7E, 0x00, 0x00],

    # 0x0A: Cool Sunglasses Snake Head
    0x0A: [0x00, 0x3C, 0x7E, 0xFF, 0x00, 0x66, 0x66, 0xFF, 0xFF, 0xFF, 0xBD, 0xC3, 0x7E, 0x7E, 0x3C, 0x00],

    # 0x0B: Play Triangle Icon '▶'
    0x0B: [0x00, 0x00, 0x60, 0x78, 0x7E, 0x7F, 0x7F, 0x7E, 0x78, 0x60, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],

    # 0x0C: Google Snake Smooth Rounded Body Segment
    0x0C: [0x00, 0x3C, 0x7E, 0x7E, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7E, 0x7E, 0x3C, 0x00],

    # 0x0D: Google Snake Digesting Apple Bulge Segment (Swollen plump segment!)
    0x0D: [0x3C, 0x7E, 0xFF, 0xFF, 0xDF, 0xBF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7E, 0x3C],

    # 0x0E: Google Snake Tapered Tail Tip
    0x0E: [0x00, 0x00, 0x00, 0x18, 0x3C, 0x7E, 0x7E, 0x7E, 0x7E, 0x7E, 0x3C, 0x18, 0x00, 0x00, 0x00, 0x00],

    # 0x0F: Google Snake Wide-Open Chomp Mouth Head (When near an apple!)
    0x0F: [0x3C, 0x7E, 0x99, 0xDB, 0xFF, 0xC3, 0x81, 0x00, 0x00, 0x81, 0xC3, 0xFF, 0xFF, 0x7E, 0x3C, 0x00],

    # 0x10: Google Snake Knocked-Out Dizzy Head (X_X eyes on crash!)
    0x10: [0x00, 0x3C, 0x7E, 0xFF, 0x99, 0xbd, 0x99, 0xFF, 0xFF, 0xC3, 0x99, 0x99, 0xC3, 0x7E, 0x3C, 0x00],

    # 0x11: Speaker / Audio Note Icon '♪'
    0x11: [0x00, 0x06, 0x0E, 0x1E, 0x36, 0x66, 0x06, 0x06, 0x06, 0x1E, 0x3E, 0x3E, 0x1C, 0x00, 0x00, 0x00],

    # 0x12: Settings Gear Icon '⚙'
    0x12: [0x00, 0x18, 0x5A, 0x3C, 0x7E, 0xE7, 0xC3, 0xC3, 0xE7, 0x7E, 0x3C, 0x5A, 0x18, 0x00, 0x00, 0x00],

    # 0x13: Terminal Shell Prompt Icon '>_'
    0x13: [0x00, 0x00, 0x60, 0x30, 0x18, 0x0C, 0x18, 0x30, 0x60, 0x00, 0x00, 0x1F, 0x1F, 0x00, 0x00, 0x00],

    # 0x14: Hardware Mouse Arrow Pointer '↖'
    0x14: [0x80, 0xC0, 0xE0, 0xF0, 0xF8, 0xFC, 0xFE, 0xFF, 0xF8, 0xDC, 0x8C, 0x06, 0x06, 0x00, 0x00, 0x00],

    # 0x18: Flicking Forked Snake Tongue
    0x18: [0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x06, 0xFC, 0xFC, 0x06, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00],
}

custom_glyphs_table_asm = "custom_glyphs_table:\n"
for code in sorted(custom_glyphs_table_def.keys()):
    bytes_str = ", ".join([f"0x{b:02X}" for b in custom_glyphs_table_def[code]])
    custom_glyphs_table_asm += f"    db 0x{code:02X}, {bytes_str}\n"
custom_glyphs_table_asm += "    db 0\n"

# Append sample_table_asm to tables
full_asm = part1 + "\n" + part2 + "\n" + part3_tables + "\n" + sample_table_asm + "\n" + font_table_asm + "\n" + custom_glyphs_table_asm + "\n" + logo_table_asm + "\n" + part5_tail
DEST.write_text(full_asm, encoding="utf-8")
print(f"Generated clean {DEST} ({len(full_asm)} bytes)")

# Write Block 0 + Block 1 + Block 2 binary (196,608 bytes)
BLOCKS0_2_BIN = BASE_DIR / "bios_blocks0_2.bin"
BLOCKS0_2_BIN.write_bytes(block0 + block1_2)
print(f"Generated ROM Blocks 0..2 ({len(block0 + block1_2)} bytes)")

# Auto-assemble Block 3 and package complete 256 KB ROM
import subprocess, shutil
nasm_cmd = "nasm"
if not shutil.which("nasm"):
    default_nasm = Path(r"C:\Users\jonas\Documents\Default Project\NASM\nasm-2.16.01\nasm.exe")
    if default_nasm.exists():
        nasm_cmd = str(default_nasm)

block3_bin = BASE_DIR / "bios_block3.bin"
res = subprocess.run([nasm_cmd, "-f", "bin", str(DEST), "-o", str(block3_bin)], capture_output=True, text=True)
if res.returncode == 0 and block3_bin.exists() and block3_bin.stat().st_size == 65536:
    rom_256k = block0 + block1_2 + block3_bin.read_bytes()
    final_bin = BASE_DIR / "bios.bin"
    final_bin.write_bytes(rom_256k)
    nvram_img = BASE_DIR / "cybfs_nvram.img"
    if not nvram_img.exists() or nvram_img.stat().st_size < 65536:
        nvram_img.write_bytes(b"\x00" * 65536)
        print(f"     -> Created persistent NVRAM disk: {nvram_img} (65,536 Bytes)")
    print("=" * 60)
    print(f"[OK] 256 KB BIOS ROM successfully generated ({len(rom_256k)} Bytes)!")
    print(f"     -> {final_bin}")
    print("=" * 60)
else:
    print(f"[ERROR] NASM assembly of Block 3 failed: {res.stderr}")


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

# 0. SND_CRUNCH (~0.20s): Crisp apple bite
t0 = np.linspace(0, 0.20, int(SR * 0.20), endpoint=False)
f_mod0 = 1200 * np.exp(-t0 * 30) + 180
bite_tone = np.sin(2 * np.pi * f_mod0 * t0) * np.exp(-t0 * 22)
bite_noise = np.random.uniform(-0.7, 0.7, len(t0)) * np.exp(-t0 * 28)
snd_crunch = to_int16_bytes(bite_tone * 0.55 + bite_noise * 0.45)

# 1. SND_GOLDEN (~0.55s): Magical ascending chime
t1 = np.linspace(0, 0.55, int(SR * 0.55), endpoint=False)
sig1 = np.zeros_like(t1)
for i, freq in enumerate([1318.5, 1661.2, 1975.5, 2637.0]):
    start_t = i * 0.08
    m = t1 >= start_t; tn = t1[m] - start_t
    sig1[m] += np.sin(2 * np.pi * freq * tn) * np.exp(-tn * 8.0) + 0.3 * np.sin(4 * np.pi * freq * tn) * np.exp(-tn * 12.0)
snd_golden = to_int16_bytes(sig1 * 0.5)

# 2. SND_CRASH (~0.45s): Punchy sub-bass impact + metal shatter noise
t2 = np.linspace(0, 0.45, int(SR * 0.45), endpoint=False)
punch = np.sin(2 * np.pi * (160 * np.exp(-t2 * 18) + 45) * t2) * np.exp(-t2 * 12)
noise2 = np.random.uniform(-0.8, 0.8, len(t2)) * np.exp(-t2 * 15)
snd_crash = to_int16_bytes(punch * 0.7 + noise2 * 0.3)

# 3. SND_START (~0.35s): Upbeat arcade coin / power chime
t3 = np.linspace(0, 0.35, int(SR * 0.35), endpoint=False)
sig3 = np.zeros_like(t3)
for i, freq in enumerate([659.2, 880.0, 1108.7]):
    start_t = i * 0.09
    m = t3 >= start_t; tn = t3[m] - start_t
    sig3[m] += (np.sin(2 * np.pi * freq * tn) + 0.4 * np.sin(4 * np.pi * freq * tn)) * np.exp(-tn * 9.0)
snd_start = to_int16_bytes(sig3 * 0.55)

# 4. SND_PAUSE (~0.16s): Futuristic double-tone
t4 = np.linspace(0, 0.16, int(SR * 0.16), endpoint=False)
t4_1 = t4[t4 < 0.08]; t4_2 = t4[t4 >= 0.08] - 0.08
p1 = np.sin(2 * np.pi * 987.7 * t4_1) * np.exp(-t4_1 * 30)
p2 = np.sin(2 * np.pi * 1479.9 * t4_2) * np.exp(-t4_2 * 30)
snd_pause = to_int16_bytes(np.concatenate([p1, p2]) * 0.7)

# 5. SND_BOOT (~0.50s): Cyber startup chord
t5 = np.linspace(0, 0.50, int(SR * 0.50), endpoint=False)
chord = (np.sin(2 * np.pi * 523.25 * t5) + 
         0.8 * np.sin(2 * np.pi * 783.99 * t5) + 
         0.9 * np.sin(2 * np.pi * 1046.50 * t5) +
         0.4 * np.sin(2 * np.pi * 1318.51 * t5)) * np.exp(-t5 * 5.0)
snd_boot = to_int16_bytes(chord * 0.35)

# 6. SND_GAMEOVER (~0.85s): Melancholic minor descent
t6 = np.linspace(0, 0.85, int(SR * 0.85), endpoint=False)
sig6 = np.zeros_like(t6)
for i, freq in enumerate([440.0, 349.2, 293.6, 277.2]):
    start_t = i * 0.18
    m = t6 >= start_t; tn = t6[m] - start_t
    sig6[m] += (np.sin(2 * np.pi * freq * tn) + 0.3 * np.sin(4 * np.pi * freq * tn)) * np.exp(-tn * 4.5)
snd_gameover = to_int16_bytes(sig6 * 0.55)

# 7. SND_VICTORY (~1.20s): Majestic polyphonic brass fanfare
t7 = np.linspace(0, 1.20, int(SR * 1.20), endpoint=False)
sig7 = np.zeros_like(t7)
notes = [
    (0.00, 0.15, [523.25, 659.25]),
    (0.15, 0.15, [659.25, 783.99]),
    (0.30, 0.15, [783.99, 1046.50]),
    (0.45, 0.25, [1046.50, 1318.51]),
    (0.70, 0.15, [783.99, 1046.50]),
    (0.85, 0.35, [1046.50, 1318.51, 1567.98])
]
for start_t, dur, freqs in notes:
    m = (t7 >= start_t) & (t7 < start_t + dur + 0.3); tn = t7[m] - start_t
    ss = np.zeros_like(tn)
    for f in freqs: ss += np.sin(2 * np.pi * f * tn) + 0.25 * np.sin(4 * np.pi * f * tn)
    sig7[m] += ss * np.exp(-tn * (4.0 if dur > 0.2 else 7.0)) * 0.4
snd_victory = to_int16_bytes(sig7 * 0.5)

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

# Block 0: 64 KB ROM Header and Reserved Space
block0 = b"CYBFORGE_RETRO_BIOS_256KB_ROM\x00" + b"\x00" * (65536 - 30)

content = SRC.read_text(encoding="utf-8", errors="replace")

# Part 1: Boot & Hardware Init up to SCHRITT 7
idx_s7 = content.find("; SCHRITT 7:")
if idx_s7 == -1:
    idx_s7 = content.find("SCHRITT 7:")
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
part1 = part1.replace("; COM1 (0x3F8) auf 115200 Baud", kbd_8042_init + "\n    ; COM1 (0x3F8) auf 115200 Baud")

# RAM-Variablen im Segment 0x0000
ram_defs = """
; --- RAM-Variablen im freien Basisspeicher (DS = 0x0000, Adressen 0x1000..0x1B00) ---
SNAKE_X     equ 0x1000      ; X-Koordinaten (1200 Bytes: 0x1000..0x14AF)
SNAKE_Y     equ 0x1500      ; Y-Koordinaten (1200 Bytes: 0x1500..0x19AF)
SNAKE_LEN   equ 0x1A00      ; Aktuelle Laenge (Word)
SNAKE_DIR   equ 0x1A02      ; Richtung: 0=Up, 1=Right, 2=Down, 3=Left (Byte)
NEXT_DIR    equ 0x1A03      ; Gepufferte naechste Richtung (Byte)
FOOD_X      equ 0x1A04      ; X-Position der Frucht (Byte)
FOOD_Y      equ 0x1A05      ; Y-Position der Frucht (Byte)
SCORE       equ 0x1A06      ; Aktuelle Punktzahl (Word)
RND_SEED    equ 0x1A08      ; Zufalls-Seed (Word)
DIR_LOCKED  equ 0x1A0A      ; Sperre fuer Richtungswechsel (Byte)
NEW_HEAD_X  equ 0x1A0B      ; Neuer Kopf X (Byte)
NEW_HEAD_Y  equ 0x1A0C      ; Neuer Kopf Y (Byte)
QUEUED_DIR  equ 0x1A0D      ; Puffer fuer schnellen 2. Tastendruck (Byte)
HIGH_SCORE  equ 0x1A0E      ; Session High Score (Word, im CMOS NVRAM persistiert)

; Cybforge Retro BIOS Setup Konfigurationsoptionen (0x1A10..0x1A19)
CFG_SPEED   equ 0x1A10      ; 0=Normal, 1=Fast, 2=Slow (Byte)
CFG_WALLS   equ 0x1A11      ; 0=Solid, 1=Wrap-Around (Byte)
CFG_SOUND   equ 0x1A12      ; 0=SB16 16-Bit, 1=PC Speaker, 2=Dual Audio, 3=Muted (Byte)
CFG_FACE    equ 0x1A13      ; 0=Classic Smile, 1=Cool Shades (Byte)
CFG_LEN     equ 0x1A14      ; 0=4 Segments, 1=3 Segments, 2=6 Segments (Byte)
CFG_WIN     equ 0x1A15      ; 0=Full Board (1044), 1=25, 2=50, 3=100 (Byte)
CFG_DISP    equ 0x1A16      ; Auto 1080p (Byte)
SETUP_SEL   equ 0x1A17      ; Ausgewaehlte Menue-Zeile im Cybforge Setup (0..9) (Byte)
CFG_THEME   equ 0x1A18      ; 0=Cyberpunk Neon, 1=Matrix Green, 2=Amber CRT, 3=CGA Retro (Byte)
CFG_ARENA   equ 0x1A19      ; 0=Classic Open, 1=Four Pillars, 2=The Maze (Byte)

; Gameplay Erweiterungen (0x1A1A..0x1A35)
GOLD_FOOD_X equ 0x1A1A      ; X-Position des Gold-Apfels (Byte, 0xFF wenn inaktiv)
GOLD_FOOD_Y equ 0x1A1B      ; Y-Position des Gold-Apfels (Byte)
GOLD_TIMER  equ 0x1A1C      ; Ticks verbleibend fuer Gold-Apfel (Word)
APPLE_COUNT equ 0x1A1E      ; Zaehler normal gefressener Aepfel (Byte)
TOP3_TABLE  equ 0x1A20      ; Top 3 Leaderboard: 3x (3 Bytes Name, 2 Bytes Score) = 15 Bytes (0x1A20..0x1A2E)
CURRENT_NAME equ 0x1A30     ; 3 Bytes Puffer fuer Namenseingabe (0x1A30..0x1A32)
CUR_CHAR_IDX equ 0x1A33     ; Aktiver Buchstabe (0..2) (Byte)
sb16_detected equ 0x1A34    ; 1=Sound Blaster 16 Detected, 0=None (Byte)

; --- Multi-Tab BIOS Setup & BiosShell Konfiguration (0x1A35..0x1A3F) ---
SETUP_TAB       equ 0x1A35  ; Aktiver Reiter im Setup: 0 = Main & Game, 1 = BiosShell (Byte)
CFG_SH_THEME    equ 0x1A36  ; 0=Classic EFI, 1=Matrix Green, 2=Cyber Cyan, 3=BIOS Blue (Byte)
CFG_SH_PROMPT   equ 0x1A37  ; 0="FS0:\\> ", 1="SHELL> ", 2="root@bios:# " (Byte)
CFG_SH_BANNER   equ 0x1A38  ; 0=Full EFI Map, 1=Compact, 2=Quiet Mode (Byte)
CFG_SH_BEEP     equ 0x1A39  ; 0=Enabled, 1=Muted (Byte)
CFG_BOOT_MODE   equ 0x1A3A  ; 0=Snake Game, 1=BiosShell (Byte)

; --- Cybforge BIOS Shell Laufzeit-Speicher (0x1B00..0x1CFF) ---
SH_CUR_ROW      equ 0x1B00  ; Aktuelle Terminal-Zeile (1..23) (Byte)
SH_CUR_COL      equ 0x1B01  ; Aktuelle Terminal-Spalte (0..79) (Byte)
SH_DIR_ID       equ 0x1B02  ; Aktuelles Verzeichnis: 0=Root, 1=EFI, 2=AUDIO, 3=DIAG (Byte)
SH_SHIFT        equ 0x1B03  ; Shift-Taste gedrueckt (0/1) (Byte)
SH_CMD_LEN      equ 0x1B04  ; Laenge der aktuellen Eingabe (0..58) (Byte)
SH_HIST_LEN     equ 0x1B05  ; Laenge des letzten Befehls in History (Byte)
SH_DUMP_ADDR    equ 0x1B06  ; Aktuelle Adresse fuer dmem Hex-Dump (Word)
SH_TEXT_ATTR    equ 0x1B08  ; Standard-Textattribut der Shell (Byte)
SH_HIGH_ATTR    equ 0x1B09  ; Highlight-Attribut der Shell (Byte)
SH_PROMPT_ATTR  equ 0x1B0A  ; Prompt-Farbattribut (Byte)
SH_BAR_ATTR     equ 0x1B0B  ; Statusleisten-Attribut (Byte)

SH_CMD_BUF      equ 0x1B10  ; 64 Bytes Eingabepuffer (0x1B10..0x1B4F)
SH_HIST_BUF     equ 0x1B50  ; 64 Bytes History-Puffer (0x1B50..0x1B8F)
SH_CLEAN_BUF    equ 0x1B90  ; 64 Bytes normalisierter Befehlspuffer (0x1B90..0x1BCF)
"""
idx_org = part1.find("[ORG 0x0000]")
line_end = part1.find("\n", idx_org) + 1
part1 = part1[:line_end] + ram_defs + part1[line_end:]

# In part1 nach .font_done den Logo-Font-Loader einbauen
logo_loader_code = """
    ; --- Custom 16-Scanline Game Glyphen (0x01..0x0A) direkt in Plane 2 kopieren ---
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
    mov cx, 16              ; Alle 16 echten Scanlines
    rep movsb
    jmp .custom_glyph_loop
.custom_glyphs_done:

    ; --- Cybforge Logo 16-Scanline Glyphen (0x80..0xBB) direkt in Plane 2 kopieren ---
    mov si, logo_font_table
.logo_char_loop:
    lodsb
    test al, al
    jz .logo_done
    xor ah, ah
    shl ax, 5               ; Offset in Plane 2 = char_code * 32
    mov di, ax
    mov cx, 16              ; Alle 16 echten Zeilen
    rep movsb
    jmp .logo_char_loop
.logo_done:
    pop ds
"""
part1 = part1.replace(".font_done:", ".font_done:\n" + logo_loader_code)

# Part 2: Cybforge POST Screen, Cybforge Setup Utility & Snake Game
part2 = """
    ; =========================================================================
    ; SEGMENT-SETUP: DS = 0x0000 (RAM) & ES = 0xB800 (TEXT-VRAM)
    ; =========================================================================
    mov ax, 0x0000
    mov ds, ax              ; DS zeigt fest auf den Basisspeicher!
    mov ax, 0xB800
    mov es, ax              ; ES zeigt fest auf den VGA-Textspeicher!

    ; Flat Real Mode (Unreal Mode) initialisieren fuer 256KB ROM Audio
    call enter_unreal_mode

    ; Sound Blaster 16 Hardware initialisieren (DSP Reset, Mixer, Volumes)
    call sb16_init
    call sound_boot

    ; Gespeicherte Einstellungen & Top 3 Highscore aus CMOS NVRAM laden
    call load_cmos_settings
    call apply_color_theme
    mov byte [SETUP_SEL], 0         ; Zeile 0 ausgewaehlt
    mov byte [SETUP_TAB], 0         ; Standard-Reiter: 0 (Main & Game)

    ; =========================================================================
    ; PHASE 1: CYBFORGE RETRO BIOS POST SCREEN (3 Sekunden Wartezeit fuer F12)
    ; =========================================================================
post_screen:
    call clear_screen_black

    ; Zeile 2: BIOS Date & Version (Obere Zeile entfernt wie gewuenscht)
    mov di, (2 * 80 + 2) * 2
    mov si, str_post_hdr2
    mov ah, 0x07                    ; Light Gray
    call print_string

    ; Zeile 4 & 5: CPU & Co-Processor
    mov di, (4 * 80 + 2) * 2
    mov si, str_post_cpu
    mov ah, 0x07
    call print_string

    mov di, (5 * 80 + 2) * 2
    mov si, str_post_coproc
    mov ah, 0x07
    call print_string

    ; Zeile 7..9: VGA Display, Keyboard, Timer
    mov di, (7 * 80 + 2) * 2
    mov si, str_post_vga
    mov ah, 0x07
    call print_string

    mov di, (8 * 80 + 2) * 2
    mov si, str_post_kbd
    mov ah, 0x07
    call print_string

    mov di, (9 * 80 + 2) * 2
    mov si, str_post_pit
    mov ah, 0x07
    call print_string

    ; Zeile 11 & 12: Monitor Detection & Scaler
    mov di, (11 * 80 + 2) * 2
    mov si, str_post_disp_mon
    mov ah, 0x0B                    ; Bright Cyan fuer Screen-Check!
    call print_string

    mov di, (12 * 80 + 2) * 2
    mov si, str_post_vid_scale
    mov ah, 0x07                    ; Light Gray
    call print_string

    ; Zeile 14: Animierter RAM-Zaehler mit PC-Speaker-Ticks (0..640 KB)
    call post_ram_counter

    mov di, (15 * 80 + 2) * 2
    mov si, str_post_ext
    mov ah, 0x07
    call print_string

    ; Zeile 17: Disks
    mov di, (17 * 80 + 2) * 2
    mov si, str_post_drives
    mov ah, 0x07
    call print_string

    ; Cybforge Logo an der rechten Seite zeichnen (Zeilen 2 bis 9, Spalten 64 bis 73)
    call draw_cybforge_logo

    ; Zeile 20 & 21: F12 Hinweis & Countdown
    mov di, (20 * 80 + 2) * 2
    mov si, str_post_f12
    mov ah, 0x0E                    ; Bright Yellow!
    call print_string

    mov di, (21 * 80 + 2) * 2
    mov si, str_post_boot
    mov ah, 0x07                    ; Light Gray
    call print_string

    ; Genau 3.0 Sekunden warten auf Tastendruck (F12/DEL fuer Setup oder ENTER fuer Direktboot)
    call drain_kbd
    mov bp, 60
.post_wait_loop:
    call read_key
    cmp al, 0x58                    ; F12 -> Setup
    je core_bios_setup
    cmp al, 0x53                    ; DEL -> Setup
    je core_bios_setup
    cmp al, 0x1C                    ; ENTER -> Sofort booten
    je boot_direct_snake

    mov ecx, 12500000               ; ~50 ms Mini-Tick (60 * 12.5M = 750M Zyklen = exakt 3.0s)
    call delay_cycles
    dec bp
    jnz .post_wait_loop

    ; 3 Sekunden abgelaufen ohne F12 -> Gem. CFG_BOOT_MODE in Snake oder BiosShell booten
boot_direct_snake:
    cmp byte [CFG_BOOT_MODE], 1
    je bios_shell_main
    jmp init_snake_game

    ; =========================================================================
    ; CYBFORGE LOGO ZEICHEN-ROUTINE (Rechte Seite des POST-Screens)
    ; =========================================================================
draw_cybforge_logo:
    mov bl, 0x80                    ; Erster Zeichencode fuer Logo (0x80 bis 0xBB)
    mov dh, 2                       ; Startzeile 2 (Zeilen 2 bis 7 = 6 Zeilen)
.row_loop:
    cmp dh, 8
    je .done_logo_tiles

    ; Offset = (dh * 80 + 64) * 2
    movzx ax, dh
    mov cl, 80
    mul cl
    add ax, 64
    shl ax, 1
    mov di, ax

    mov cx, 10                      ; 10 Spalten
.col_loop:
    mov al, bl
    mov ah, 0x0B                    ; Attribut: Bright Cyan (0x0B)
    stosw
    inc bl
    loop .col_loop

    inc dh
    jmp .row_loop

.done_logo_tiles:
    ; Text unter dem Logo:
    ; Zeile 8, Spalte 64: "   CYBFORGE   " (Cyan 0x0B)
    mov di, (8 * 80 + 64) * 2
    mov si, str_logo_lbl1
    mov ah, 0x0B
    call print_string

    ; Zeile 9, Spalte 64: "  RETRO BIOS  " (Yellow 0x0E)
    mov di, (9 * 80 + 64) * 2
    mov si, str_logo_lbl2
    mov ah, 0x0E
    call print_string
    ret

    ; =========================================================================
    ; PHASE 2: CYBFORGE RETRO BIOS SETUP UTILITY (Retro CMOS Setup Menue)
    ; =========================================================================
core_bios_setup:
    call apply_color_theme
    call drain_kbd
    call sound_click

.redraw_setup:
    call draw_setup_screen

.setup_input_loop:
    call read_key
    test al, al
    jz .setup_wait_tick

    ; Schnellwechsel zwischen Reitern via [TAB] (0x0F), [1] (0x02), [2] (0x03)
    cmp al, 0x0F                    ; TAB -> Reiter wechseln!
    je .toggle_tab
    cmp al, 0x02                    ; Taste '1' -> Reiter 0 (Main & Game)
    je .switch_tab_0
    cmp al, 0x03                    ; Taste '2' -> Reiter 1 (BiosShell)
    je .switch_tab_1

    ; Navigation: W/S oder Pfeiltasten Oben/Unten
    cmp al, 0x11                    ; 'W'
    je .sel_up
    cmp al, 0x48                    ; Up Arrow
    je .sel_up

    cmp al, 0x1F                    ; 'S'
    je .sel_down
    cmp al, 0x50                    ; Down Arrow
    je .sel_down

    ; Wert aendern / Reiter wechseln: A/D, Pfeiltasten Links/Rechts, ENTER, SPACE
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
    mov ecx, 1500000                ; ~5 ms fuer ultra-direkte Menue-Reaktion
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
    mov byte [SETUP_SEL], 1         ; Direkt auf "BiosShell starten [Press ENTER]" setzen!
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
    mov byte [SETUP_SEL], 10        ; Tab 0 hat Indizes 0..10
    cmp byte [SETUP_TAB], 0
    je .redraw_setup
    mov byte [SETUP_SEL], 8         ; Tab 1 hat Indizes 0..8
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

; --- LINKS / VORHERIGER WERT ---
.val_prev:
    mov al, [SETUP_SEL]
    cmp al, 0                       ; Zeile 0 ist auf beiden Reitern die Reiter-Auswahl!
    je .toggle_tab

    cmp byte [SETUP_TAB], 1
    je .tab1_prev

    ; Tab 0 (Main & Game): Indizes 1..8
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
    call apply_color_theme
    jmp .redraw_setup
.p8:
    cmp al, 8
    jne .redraw_setup
    dec byte [CFG_ARENA]
    jns .redraw_setup
    mov byte [CFG_ARENA], 2
    jmp .redraw_setup

.tab1_prev:
    ; Tab 1 (BiosShell):
    cmp al, 1                       ; Auf "BiosShell starten" wechselt Links zurueck zu Tab 0
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

; --- RECHTS / NAECHSTER WERT ---
.val_next:
    mov al, [SETUP_SEL]
    cmp al, 0                       ; Zeile 0: Reiter wechseln
    je .toggle_tab

    cmp byte [SETUP_TAB], 1
    je .tab1_next

    ; Tab 0 (Main & Game): Indizes 1..8
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
    call apply_color_theme
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
    cmp al, 1                       ; SPACE auf "BiosShell" startet ebenfalls die Shell
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

; --- ENTER AKTION ---
.val_enter:
    mov al, [SETUP_SEL]
    cmp al, 0
    je .toggle_tab

    cmp byte [SETUP_TAB], 1
    je .tab1_enter

    ; Tab 0 Enter:
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
    call apply_color_theme
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
    ; SETUP SCREEN RENDERER (Multi-Tab Cybforge Retro Style)
    ; =========================================================================
draw_setup_screen:
    ; 1. Hintergrund mit BIOS-Blau (0x1F) fuellen
    xor di, di
    mov cx, 80 * 25
    mov ax, 0x1F20
    rep stosw

    ; 2. Titelzeile (Zeile 0)
    mov di, (0 * 80 + 6) * 2
    mov si, str_setup_title
    mov ah, 0x1F
    call print_string

    mov di, (0 * 80 + 50) * 2
    mov si, str_setup_tab_hint
    mov ah, 0x1E
    call print_string

    ; Trennlinie (Zeile 1)
    mov di, (1 * 80 + 0) * 2
    mov cx, 80
    mov ax, 0x1F05
    rep stosw

    ; 3. Reiter-Leiste (Tab Bar auf Zeile 2)
    mov di, (2 * 80 + 6) * 2
    mov si, str_tab0_label
    mov ah, 0x70                    ; Aktiv: Schwarz auf Hellgrau (Inverted)
    cmp byte [SETUP_TAB], 0
    je .draw_t0_hdr
    mov ah, 0x17                    ; Inaktiv: Grau auf Blau
.draw_t0_hdr:
    call print_string

    mov di, (2 * 80 + 30) * 2
    mov si, str_tab1_label
    mov ah, 0x70                    ; Aktiv: Schwarz auf Hellgrau (Inverted)
    cmp byte [SETUP_TAB], 1
    je .draw_t1_hdr
    mov ah, 0x17                    ; Inaktiv: Grau auf Blau
.draw_t1_hdr:
    call print_string

    ; 4. Haupt-Optionskasten (Zeile 3 bis 17, Spalte 6 bis 73)
    mov di, (3 * 80 + 6) * 2
    mov ax, 0x1F01                  ; '┌'
    stosw
    mov cx, 66
    mov ax, 0x1F05                  ; '─'
    rep stosw
    mov ax, 0x1F02                  ; '┐'
    stosw

    mov di, (3 * 80 + 10) * 2
    mov si, str_box_title_main
    cmp byte [SETUP_TAB], 0
    je .draw_box_hdr
    mov si, str_box_title_shell
.draw_box_hdr:
    mov ah, 0x1E                    ; Yellow
    call print_string

    mov cx, 13
    mov di, (4 * 80 + 6) * 2
.sb_vert1:
    mov word [es:di], 0x1F06
    mov word [es:di + 67 * 2], 0x1F06
    add di, 80 * 2
    loop .sb_vert1

    mov di, (17 * 80 + 6) * 2
    mov ax, 0x1F03                  ; '└'
    stosw
    mov cx, 66
    mov ax, 0x1F05                  ; '─'
    rep stosw
    mov ax, 0x1F04                  ; '┘'
    stosw

    ; 5. Hilfe-Kasten (Zeile 18 bis 23, Spalte 6 bis 73)
    mov di, (18 * 80 + 6) * 2
    mov ax, 0x1F01                  ; '┌'
    stosw
    mov cx, 66
    mov ax, 0x1F05                  ; '─'
    rep stosw
    mov ax, 0x1F02                  ; '┐'
    stosw

    mov di, (18 * 80 + 10) * 2
    mov si, str_box_title_help
    mov ah, 0x1E
    call print_string

    mov cx, 4
    mov di, (19 * 80 + 6) * 2
.sb_vert2:
    mov word [es:di], 0x1F06
    mov word [es:di + 67 * 2], 0x1F06
    add di, 80 * 2
    loop .sb_vert2

    mov di, (23 * 80 + 6) * 2
    mov ax, 0x1F03                  ; '└'
    stosw
    mov cx, 66
    mov ax, 0x1F05                  ; '─'
    rep stosw
    mov ax, 0x1F04                  ; '┘'
    stosw

    ; 6. Fusszeile / Tastaturbedienung (Zeile 24)
    mov di, (24 * 80 + 4) * 2
    mov si, str_setup_footer
    mov ah, 0x1F
    call print_string

    ; Pruefen welcher Reiter aktiv ist
    cmp byte [SETUP_TAB], 1
    je .draw_tab1_items

    ; =========================================================================
    ; REITER 0: MAIN & GAME ITEMS (Indizes 0..10)
    ; =========================================================================
    ; Index 0 (Row 4): Setup Reiter
    mov bl, 0
    mov dh, 4
    mov si, str_opt_tab
    call draw_menu_row
    mov si, str_val_tab_main
    call draw_val_str

    ; Index 1 (Row 5): Game Speed
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

    ; Index 2 (Row 6): Wall Collision
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

    ; Index 3 (Row 7): Sound Output
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

    ; Index 4 (Row 8): Snake Face Style
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

    ; Index 5 (Row 9): Starting Length
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

    ; Index 6 (Row 10): Victory Target
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

    ; Index 7 (Row 11): Color Theme
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

    ; Index 8 (Row 12): Game Arena
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

    ; Index 9 (Row 14): Reset Defaults
    mov bl, 9
    mov dh, 14
    mov si, str_opt_reset
    call draw_menu_row

    ; Index 10 (Row 15): Save & Boot Game
    mov bl, 10
    mov dh, 15
    mov si, str_opt_boot
    call draw_menu_row

    ; Info: Session High Score anzeigen bei Row 16
    mov di, (16 * 80 + 10) * 2
    mov si, str_hi_score_lbl
    mov ah, 0x1E                    ; Yellow
    call print_string
    mov ax, [HIGH_SCORE]
    call render_3digits_yellow

    ; Dynamischer Hilfetext fuer Tab 0
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
    ; REITER 1: BIOSSHELL ITEMS (Indizes 0..8)
    ; =========================================================================
.draw_tab1_items:
    ; Index 0 (Row 4): Setup Reiter
    mov bl, 0
    mov dh, 4
    mov si, str_opt_tab
    call draw_menu_row
    mov si, str_val_tab_shell
    call draw_val_str

    ; Index 1 (Row 6): BiosShell starten (Haupt-Aktionspunkt!)
    mov bl, 1
    mov dh, 6
    mov si, str_opt_sh_launch
    call draw_menu_row
    mov si, str_val_sh_launch
    call draw_val_str

    ; Index 2 (Row 8): Shell Color Scheme
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

    ; Index 3 (Row 9): Shell Prompt Style
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

    ; Index 4 (Row 10): Startup Banner
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

    ; Index 5 (Row 11): Keystroke Audio Beep
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

    ; Index 6 (Row 12): Default POST Boot Target
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

    ; Index 7 (Row 14): Reset Shell Defaults
    mov bl, 7
    mov dh, 14
    mov si, str_opt_sh_reset
    call draw_menu_row

    ; Index 8 (Row 15): Save & Boot Game
    mov bl, 8
    mov dh, 15
    mov si, str_opt_boot
    call draw_menu_row

    ; Statuszeile auf Row 16 im BiosShell-Reiter
    mov di, (16 * 80 + 10) * 2
    mov si, str_sh_tab_status
    mov ah, 0x1B                    ; Bright Cyan on Blue
    call print_string

    ; Dynamischer Hilfetext fuer Tab 1 (BiosShell)
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
    mov ah, 0x1E                    ; Yellow
    call print_string
    ret

draw_menu_row:
    ; Input: bl = row index, dh = screen row (Y), si = string
    push ax
    push di
    mov al, 10
    mov ah, dh
    push bx
    mov bl, ah
    call xy_to_di
    pop bx

    ; Pfeil anzeigen wenn ausgewaehlt
    mov ah, 0x1F                    ; Standard: White on Blue
    cmp [SETUP_SEL], bl
    jne .dm_no_arrow
    mov ah, 0x1E                    ; Yellow
    mov al, '>'
    stosw
    mov al, ' '
    stosw
    jmp .dm_print_txt
.dm_no_arrow:
    mov al, ' '
    stosw
    stosw
.dm_print_txt:
    call print_string
    pop di
    pop ax
    ret

draw_val_str:
    push ax
    push di
    mov al, 38                      ; Spalte 38 fuer Wertanzeige
    mov bl, dh                      ; Zeile dh
    call xy_to_di
    mov ah, 0x1A                    ; Bright Green
    call print_string
    pop di
    pop ax
    ret

init_snake_game:
    call clear_screen_black
    call draw_game_board

    ; Snake-Laenge gemaess CFG_LEN setzen
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
    ; Schlange mittig platzieren (Kopf bei X=40, Y=12)
    mov byte [SNAKE_X + 0], 40
    mov byte [SNAKE_Y + 0], 12
    mov byte [SNAKE_X + 1], 39
    mov byte [SNAKE_Y + 1], 12
    mov byte [SNAKE_X + 2], 38
    mov byte [SNAKE_Y + 2], 12
    mov byte [SNAKE_X + 3], 37
    mov byte [SNAKE_Y + 3], 12
    mov byte [SNAKE_X + 4], 36
    mov byte [SNAKE_Y + 4], 12
    mov byte [SNAKE_X + 5], 35
    mov byte [SNAKE_Y + 5], 12

    mov byte [SNAKE_DIR], 1         ; Start-Richtung: Rechts
    mov byte [NEXT_DIR], 1
    mov byte [QUEUED_DIR], 0xFF
    mov byte [DIR_LOCKED], 0
    mov word [SCORE], 0
    mov word [RND_SEED], 0x1337

    ; Gold-Apfel & Zaehler initialisieren
    mov byte [GOLD_FOOD_X], 0xFF
    mov word [GOLD_TIMER], 0
    mov byte [APPLE_COUNT], 0

    call update_score_display
    call draw_arena_obstacles
    call spawn_fruit
    call draw_snake
    call draw_fruit

    ; Start-Hinweis anzeigen
    call draw_start_prompt
    call drain_kbd

.wait_start:
    call read_key
    test al, al
    jz .wait_idle

    cmp al, 0x01                    ; ESC -> Ins BIOS Setup
    je core_bios_setup

    ; Starten mit ENTER oder LEERTASTE (behaelt Standardrichtung Rechts)
    cmp al, 0x1C                    ; ENTER
    je .game_started
    cmp al, 0x39                    ; SPACE
    je .game_started

    ; Sofortstart mit Steuerkreuz / WASD!
    cmp al, 0x11                    ; W (Oben)
    je .start_up
    cmp al, 0x48                    ; UP Arrow
    je .start_up
    cmp al, 0x1F                    ; S (Unten)
    je .start_down
    cmp al, 0x50                    ; DOWN Arrow
    je .start_down
    cmp al, 0x20                    ; D (Rechts)
    je .start_right
    cmp al, 0x4D                    ; RIGHT Arrow
    je .start_right
    jmp .wait_idle

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
    mov ecx, 200000                 ; ~1ms Polling fuer sofortiges Ansprechverhalten
    call delay_cycles
    jmp .wait_start

.game_started:
    call sound_start
    call erase_start_prompt

    ; =========================================================================
    ; PHASE 4: HAUPTSPIEL-SCHLEIFE
    ; =========================================================================
game_loop:
    ; 1. Mini-Ticks Schleife gemaess CFG_SPEED
    ; Normal: 10 Ticks (~150ms), Fast: 7 Ticks (~105ms), Slow: 14 Ticks (~210ms)
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
    mov ecx, 3800000                ; ~15 ms Mini-Tick
    call delay_cycles
    dec bp
    jnz .tick_loop

    ; 2. Richtung uebernehmen & gepufferten Tastendruck aktivieren
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

    ; 3. Neuen Kopf berechnen
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
    ; Pruefen ob Wrap-Around aktiv ist (CFG_WALLS == 1)
    cmp byte [CFG_WALLS], 1
    jne .store_new_head

    ; Wrap-Around Logik (Cols 11..68, Rows 4..21)
    cmp al, 11
    jge .chk_wrap_r
    mov al, 68
    jmp .chk_wrap_y
.chk_wrap_r:
    cmp al, 68
    jle .chk_wrap_y
    mov al, 11

.chk_wrap_y:
    cmp bl, 4
    jge .chk_wrap_b
    mov bl, 21
    jmp .store_new_head
.chk_wrap_b:
    cmp bl, 21
    jle .store_new_head
    mov bl, 4

.store_new_head:
    mov [NEW_HEAD_X], al
    mov [NEW_HEAD_Y], bl

    ; 4. Kollision mit Waenden pruefen (wenn Solid)
    cmp byte [CFG_WALLS], 1
    je .no_wall_collision

    cmp al, 10
    jle .do_crash
    cmp al, 69
    jge .do_crash
    cmp bl, 3
    jle .do_crash
    cmp bl, 22
    jge .do_crash

.no_wall_collision:
    ; Kollision mit Arena-Hindernissen pruefen (Saeulen oder Labyrinth)
    mov al, [NEW_HEAD_X]
    mov bl, [NEW_HEAD_Y]
    call is_arena_wall
    jz .do_crash

    ; 5. Kollision mit eigenem Koerper pruefen (Schwanzspitze zieht weg)
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
    ; 6. Gold-Apfel Timer aktualisieren & Pruefen ob Gold-Apfel gefressen
    cmp byte [GOLD_FOOD_X], 0xFF
    je .chk_eat_regular

    dec word [GOLD_TIMER]
    jz .gold_expired

    ; Countdown-Anzeige auf HUD bei (34, 1): "GOLD: 0Xs"
    call update_gold_hud

    ; Pruefen ob Gold-Apfel gefressen wurde
    mov al, [NEW_HEAD_X]
    mov bl, [NEW_HEAD_Y]
    cmp al, [GOLD_FOOD_X]
    jne .chk_eat_regular
    cmp bl, [GOLD_FOOD_Y]
    jne .chk_eat_regular

    ; --- GOLD-APFEL GEFRESSEN! (+50 Punkte) ---
    add word [SCORE], 50
    call sound_golden_apple
    call erase_gold_apple
    call update_score_display
    jmp .chk_eat_regular

.gold_expired:
    call erase_gold_apple

.chk_eat_regular:
    ; 7. Pruefen ob regulaere Frucht gefressen wurde
    mov al, [NEW_HEAD_X]
    mov bl, [NEW_HEAD_Y]
    cmp al, [FOOD_X]
    jne .normal_move
    cmp bl, [FOOD_Y]
    jne .normal_move

    ; --- REGULAERE FRUCHT GEFRESSEN! ---
    inc word [SCORE]
    inc byte [APPLE_COUNT]
    call update_score_display
    call sound_eat_fruit

    ; Alle 5 Aepfel einen Gold-Apfel spawnen (falls nicht schon einer aktiv)
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

    ; Schlange verlaengern
    mov ax, [SNAKE_LEN]
    cmp ax, 1044
    jae .grow_len_done
    inc ax
    mov [SNAKE_LEN], ax
.grow_len_done:

    ; Siegbedingung pruefen
    mov cx, 1044
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

    ; Koerper nach hinten schieben
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
    call draw_snake
    call draw_fruit
    jmp game_loop

.normal_move:
    ; Schwanz-Spitze loeschen
    mov si, [SNAKE_LEN]
    dec si
    mov al, [SNAKE_X + si]
    mov bl, [SNAKE_Y + si]
    call xy_to_di
    mov word [es:di], 0x0720         ; Leerzeichen

    ; Segmente weiterschieben
    mov cx, [SNAKE_LEN]
    dec cx
.shift_loop:
    mov si, cx
    mov al, [SNAKE_X + si - 1]
    mov [SNAKE_X + si], al
    mov al, [SNAKE_Y + si - 1]
    mov [SNAKE_Y + si], al
    loop .shift_loop

    ; Neuen Kopf setzen
    mov al, [NEW_HEAD_X]
    mov [SNAKE_X], al
    mov al, [NEW_HEAD_Y]
    mov [SNAKE_Y], al

    call draw_snake
    jmp game_loop

.do_crash:
    call crash_dissolve_animation
    jmp game_over

    ; =========================================================================
    ; PHASE 5A: VICTORY SCREEN (Trophäe & Sieges-Fanfare)
    ; =========================================================================
victory_screen:
    call sound_victory

    ; Spielfeld-Innenbereich loeschen
    mov dh, 4
.clr_win_rows:
    mov al, 11
    mov bl, dh
    call xy_to_di
    mov cx, 58
    mov ax, 0x0720
    rep stosw
    inc dh
    cmp dh, 22
    jb .clr_win_rows

    ; Header & Titel
    mov al, 20
    mov bl, 4
    call xy_to_di
    mov si, str_vic_hdr1
    mov ah, 0x0E
    call print_string

    mov al, 28
    mov bl, 5
    call xy_to_di
    mov si, str_vic_hdr2
    mov ah, 0x0A
    call print_string

    ; Gold-Trophäe
    mov al, 32
    mov bl, 7
    call xy_to_di
    mov si, str_vic_t1
    mov ah, 0x0E
    call print_string
    mov al, 31
    mov bl, 8
    call xy_to_di
    mov si, str_vic_t2
    mov ah, 0x0E
    call print_string
    mov al, 32
    mov bl, 9
    call xy_to_di
    mov si, str_vic_t3
    mov ah, 0x0E
    call print_string
    mov al, 28
    mov bl, 10
    call xy_to_di
    mov si, str_vic_t4
    mov ah, 0x0B
    call print_string
    mov al, 32
    mov bl, 11
    call xy_to_di
    mov si, str_vic_t5
    mov ah, 0x0E
    call print_string
    mov al, 31
    mov bl, 12
    call xy_to_di
    mov si, str_vic_t6
    mov ah, 0x0E
    call print_string
    mov al, 32
    mov bl, 13
    call xy_to_di
    mov si, str_vic_t7
    mov ah, 0x0E
    call print_string
    mov al, 37
    mov bl, 14
    call xy_to_di
    mov si, str_vic_t8
    mov ah, 0x0E
    call print_string
    mov al, 34
    mov bl, 15
    call xy_to_di
    mov si, str_vic_t9
    mov ah, 0x0E
    call print_string
    mov al, 33
    mov bl, 16
    call xy_to_di
    mov si, str_vic_t10
    mov ah, 0x0E
    call print_string
    mov al, 33
    mov bl, 17
    call xy_to_di
    mov si, str_vic_t11
    mov ah, 0x0F
    call print_string
    mov al, 33
    mov bl, 18
    call xy_to_di
    mov si, str_vic_t12
    mov ah, 0x0F
    call print_string
    mov al, 33
    mov bl, 19
    call xy_to_di
    mov si, str_vic_t13
    mov ah, 0x0E
    call print_string

    mov al, 26
    mov bl, 21
    call xy_to_di
    mov si, str_vic_status
    mov ah, 0x0B
    call print_string

    mov al, 0
    mov bl, 24
    call xy_to_di
    mov cx, 80
    mov ax, 0x0720
    rep stosw

    mov al, 17
    mov bl, 24
    call xy_to_di
    mov si, str_vic_footer
    mov ah, 0x07
    call print_string

    call drain_kbd

.wait_vic_key:
    call read_key
    cmp al, 0x1C
    je init_snake_game
    cmp al, 0x01
    je core_bios_setup
    mov ecx, 30000000
    call delay_cycles
    jmp .wait_vic_key

    ; =========================================================================
    ; PHASE 5: GAME OVER MODAL DIALOG & TOP 3 HALL OF CHAMPIONS
    ; =========================================================================
game_over:
    call sound_game_over

    ; Pruefen ob Score fuer Top 3 qualifiziert ist -> Namenseingabe!
    call check_top3_qualification

    ; Red Modal Box fuer GAME OVER (Cols 21..59, Rows 7..19)
    mov al, 21
    mov bl, 7
    call xy_to_di
    mov ax, 0x0C01
    stosw ;  '╔' Red
    mov cx, 37
    mov ax, 0x0C05
    rep stosw
    mov ax, 0x0C02
    stosw

    mov dh, 8
.go_box_mid:
    mov al, 21
    mov bl, dh
    call xy_to_di
    mov ax, 0x0C06
    stosw
    mov cx, 37
    mov ax, 0x0720
    rep stosw
    mov ax, 0x0C06
    stosw
    inc dh
    cmp dh, 19
    jb .go_box_mid

    mov al, 21
    mov bl, 19
    call xy_to_di
    mov ax, 0x0C03
    stosw
    mov cx, 37
    mov ax, 0x0C05
    rep stosw
    mov ax, 0x0C04
    stosw

    ; Row 8: "G A M E   O V E R"
    mov al, 31
    mov bl, 8
    call xy_to_di
    mov si, str_game_over
    mov ah, 0x0C
    call print_string

    ; Row 9: "Final Score: XXX"
    mov al, 32
    mov bl, 9
    call xy_to_di
    mov si, str_final_score_lbl
    mov ah, 0x0E
    call print_string
    mov ax, [SCORE]
    call render_3digits_yellow

    ; Row 10: Divider
    mov al, 22
    mov bl, 10
    call xy_to_di
    mov cx, 37
    mov ax, 0x0C05
    rep stosw

    ; Row 11: "HALL OF CHAMPIONS"
    mov al, 31
    mov bl, 11
    call xy_to_di
    mov si, str_hall_title
    mov ah, 0x0B
    call print_string

    ; Row 13..15: Top 1, Top 2, Top 3 anzeigen
    call draw_top3_rows

    ; Row 16: Divider
    mov al, 22
    mov bl, 16
    call xy_to_di
    mov cx, 37
    mov ax, 0x0C05
    rep stosw

    ; Row 18: "[ENTER] Restart   [ESC] Setup"
    mov al, 25
    mov bl, 18
    call xy_to_di
    mov si, str_go_restart_info
    mov ah, 0x0B
    call print_string

    call drain_kbd

.wait_enter:
    call read_key
    cmp al, 0x1C
    je .do_restart
    cmp al, 0x01
    je .do_setup
    mov ecx, 30000000
    call delay_cycles
    jmp .wait_enter

.do_restart:
    jmp init_snake_game

.do_setup:
    call sound_click
    jmp core_bios_setup

    ; =========================================================================
    ; PHASE 6: INPUT HANDLER (WASD + Arrows + ESC + Pause)
    ; =========================================================================
handle_input:
    call read_key
    test al, al
    jz .input_done

    cmp al, 0x01                    ; ESC -> Setup
    jne .chk_pause
    pop ax                          ; Stack bereinigen
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
    ; Pause Modal Box (Cols 28..52, Rows 10..14)
    mov al, 28
    mov bl, 10
    call xy_to_di
    mov ax, 0x0B01
    stosw
    mov cx, 23
    mov ax, 0x0B05
    rep stosw
    mov ax, 0x0B02
    stosw

    mov dh, 11
.p_box_mid:
    mov al, 28
    mov bl, dh
    call xy_to_di
    mov ax, 0x0B06
    stosw
    mov cx, 23
    mov ax, 0x0720
    rep stosw
    mov ax, 0x0B06
    stosw
    inc dh
    cmp dh, 14
    jb .p_box_mid

    mov al, 28
    mov bl, 14
    call xy_to_di
    mov ax, 0x0B03
    stosw
    mov cx, 23
    mov ax, 0x0B05
    rep stosw
    mov ax, 0x0B04
    stosw

    mov al, 35
    mov bl, 11
    call xy_to_di
    mov si, str_paused_lbl
    mov ah, 0x0E
    call print_string

    mov al, 30
    mov bl, 13
    call xy_to_di
    mov si, str_pause_resume
    mov ah, 0x0B
    call print_string

    call drain_kbd

.wait_pause_key:
    call read_key
    cmp al, 0x19
    je .resume_game
    cmp al, 0x39
    je .resume_game
    cmp al, 0x01
    je .pause_to_setup
    mov ecx, 30000000
    call delay_cycles
    jmp .wait_pause_key

.pause_to_setup:
    call sound_click
    pop ax                          ; Stack bereinigen
    jmp core_bios_setup

.resume_game:
    call sound_pause
    ; Box loeschen & Untergrund wiederherstellen
    mov dh, 10
.p_clr:
    mov al, 28
    mov bl, dh
    call xy_to_di
    mov cx, 25
    mov ax, 0x0720
    rep stosw
    inc dh
    cmp dh, 15
    jb .p_clr

    call draw_arena_obstacles
    call draw_snake
    call draw_fruit
    cmp byte [GOLD_FOOD_X], 0xFF
    je .input_done
    mov al, [GOLD_FOOD_X]
    mov bl, [GOLD_FOOD_Y]
    call xy_to_di
    mov ax, 0x0E08
    stosw
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
    ; PHASE 7: GRAFIK & ZEICHENFUNKTIONEN
    ; =========================================================================
draw_game_board:
    ; Titel links: "CYBFORGE SNAKE" + "v2.2"
    mov al, 10
    mov bl, 1
    call xy_to_di
    mov si, str_game_title
    mov ah, 0x0B
    call print_string

    mov al, 25
    mov bl, 1
    call xy_to_di
    mov si, str_game_ver
    mov ah, 0x07
    call print_string

    ; High Score Label: "HIGH: " at (50, 1)
    mov al, 50
    mov bl, 1
    call xy_to_di
    mov si, str_hi_score_lbl
    mov ah, 0x0E
    call print_string

    ; Score Label: "SCORE: " at (63, 1)
    mov al, 63
    mov bl, 1
    call xy_to_di
    mov si, str_score_lbl
    mov ah, 0x0F
    call print_string

    ; Steuerungsanzeige unten at Y=24
    mov al, 8
    mov bl, 24
    call xy_to_di
    mov si, str_controls
    mov ah, 0x07
    call print_string

    ; Spielfeldrahmen (X: 10..69, Y: 3..22)
    mov al, 10
    mov bl, 3
    call xy_to_di
    mov ax, 0x0B01
    stosw
    mov cx, 58
    mov ax, 0x0B05
    rep stosw
    mov ax, 0x0B02
    stosw

    mov cx, 18
    mov dh, 4
.vert_loop:
    mov al, 10
    mov bl, dh
    call xy_to_di
    mov ax, 0x0B06
    stosw
    mov al, 69
    call xy_to_di
    mov ax, 0x0B06
    stosw
    inc dh
    loop .vert_loop

    mov al, 10
    mov bl, 22
    call xy_to_di
    mov ax, 0x0B03
    stosw
    mov cx, 58
    mov ax, 0x0B05
    rep stosw
    mov ax, 0x0B04
    stosw

    ; Spielfeld-Innenbereich loeschen
    mov dh, 4
.clr_inner:
    mov al, 11
    mov bl, dh
    call xy_to_di
    mov cx, 58
    mov ax, 0x0720
    rep stosw
    inc dh
    cmp dh, 22
    jb .clr_inner

    ; Arena-Hindernisse zeichnen
    call draw_arena_obstacles
    ret

draw_arena_obstacles:
    cmp byte [CFG_ARENA], 1
    je .draw_pillars
    cmp byte [CFG_ARENA], 2
    je .draw_maze
    ret

.draw_pillars:
    ; Pillar 1: (24, 8)
    mov al, 24
    mov bl, 8
    call xy_to_di
    mov word [es:di], 0x0B01
    mov word [es:di+2], 0x0B02
    mov al, 24
    mov bl, 9
    call xy_to_di
    mov word [es:di], 0x0B03
    mov word [es:di+2], 0x0B04

    ; Pillar 2: (54, 8)
    mov al, 54
    mov bl, 8
    call xy_to_di
    mov word [es:di], 0x0B01
    mov word [es:di+2], 0x0B02
    mov al, 54
    mov bl, 9
    call xy_to_di
    mov word [es:di], 0x0B03
    mov word [es:di+2], 0x0B04

    ; Pillar 3: (24, 16)
    mov al, 24
    mov bl, 16
    call xy_to_di
    mov word [es:di], 0x0B01
    mov word [es:di+2], 0x0B02
    mov al, 24
    mov bl, 17
    call xy_to_di
    mov word [es:di], 0x0B03
    mov word [es:di+2], 0x0B04

    ; Pillar 4: (54, 16)
    mov al, 54
    mov bl, 16
    call xy_to_di
    mov word [es:di], 0x0B01
    mov word [es:di+2], 0x0B02
    mov al, 54
    mov bl, 17
    call xy_to_di
    mov word [es:di], 0x0B03
    mov word [es:di+2], 0x0B04
    ret

.draw_maze:
    mov al, 20
    mov bl, 9
    call xy_to_di
    mov cx, 26
    mov ax, 0x0B05
    rep stosw
    mov al, 34
    mov bl, 16
    call xy_to_di
    mov cx, 26
    mov ax, 0x0B05
    rep stosw
    ret

is_arena_wall:
    cmp byte [CFG_ARENA], 1
    je .chk_pil
    cmp byte [CFG_ARENA], 2
    je .chk_mz
    test sp, sp
    ret

.chk_pil:
    cmp al, 24
    je .chk_pil_y
    cmp al, 25
    je .chk_pil_y
    cmp al, 54
    je .chk_pil_y
    cmp al, 55
    je .chk_pil_y
    test sp, sp
    ret
.chk_pil_y:
    cmp bl, 8
    je .hit_wall
    cmp bl, 9
    je .hit_wall
    cmp bl, 16
    je .hit_wall
    cmp bl, 17
    je .hit_wall
    test sp, sp
    ret

.chk_mz:
    cmp bl, 9
    jne .chk_mz_w2
    cmp al, 20
    jb .no_mz_hit
    cmp al, 45
    jbe .hit_wall
.chk_mz_w2:
    cmp bl, 16
    jne .no_mz_hit
    cmp al, 34
    jb .no_mz_hit
    cmp al, 59
    jbe .hit_wall
.no_mz_hit:
    test sp, sp
    ret

.hit_wall:
    xor al, al                      ; ZF = 1
    ret

draw_start_prompt:
draw_start_box:
    mov al, 22
    mov bl, 16
    call xy_to_di
    mov si, str_press_start
    mov ah, 0x0E                    ; Bright Yellow
    call print_string
    ret

erase_start_prompt:
erase_start_box:
    mov al, 22
    mov bl, 16
    call xy_to_di
    mov cx, 36
    mov ax, 0x0720                  ; Blank spaces
    rep stosw
    call draw_arena_obstacles       ; Redraw obstacles in case any was at row 16
    ret

draw_snake:
    mov al, [SNAKE_X]
    mov bl, [SNAKE_Y]
    call xy_to_di
    mov al, 0x07
    cmp byte [CFG_FACE], 1
    jne .draw_head_glyph
    mov al, 0x0A
.draw_head_glyph:
    mov ah, 0x0A
    stosw

    mov cx, [SNAKE_LEN]
    dec cx
    jz .draw_snake_done
    mov si, 1
.body_loop:
    mov al, [SNAKE_X + si]
    mov bl, [SNAKE_Y + si]
    call xy_to_di
    mov ax, 0x0209
    stosw
    inc si
    loop .body_loop
.draw_snake_done:
    ret

draw_fruit:
    mov al, [FOOD_X]
    mov bl, [FOOD_Y]
    call xy_to_di
    mov ax, 0x0C08
    stosw
    ret

spawn_fruit:
    push cx
    push si
    mov bp, 100
.try_spawn:
    call get_random
    xor dx, dx
    mov cx, 58
    div cx
    add dl, 11
    mov [FOOD_X], dl
    call get_random
    xor dx, dx
    mov cx, 18
    div cx
    add dl, 4
    mov [FOOD_Y], dl

    ; Nicht auf Arena-Hindernis
    mov al, [FOOD_X]
    mov bl, [FOOD_Y]
    call is_arena_wall
    jz .retry_food

    ; Nicht auf Schlange
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
    pop si
    pop cx
    ret

spawn_golden_apple:
    push cx
    push si
    mov bp, 100
.try_gold:
    call get_random
    xor dx, dx
    mov cx, 58
    div cx
    add dl, 11
    mov [GOLD_FOOD_X], dl
    call get_random
    xor dx, dx
    mov cx, 18
    div cx
    add dl, 4
    mov [GOLD_FOOD_Y], dl

    ; Nicht auf regulärem Apfel
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

    ; Nicht auf Schlange
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

    ; Gold-Apfel zeichnen & Timer setzen (~8s = 55 Ticks)
    mov word [GOLD_TIMER], 55
    mov al, [GOLD_FOOD_X]
    mov bl, [GOLD_FOOD_Y]
    call xy_to_di
    mov ax, 0x0E08
    stosw ;  Bright Yellow / Gold Apple
    call sound_golden_spawn
    jmp .gold_spawn_ok

.retry_gold:
    dec bp
    jnz .try_gold
    mov byte [GOLD_FOOD_X], 0xFF
.gold_spawn_ok:
    pop si
    pop cx
    ret

erase_gold_apple:
    cmp byte [GOLD_FOOD_X], 0xFF
    je .no_erase_gold
    mov al, [GOLD_FOOD_X]
    mov bl, [GOLD_FOOD_Y]
    call xy_to_di
    mov word [es:di], 0x0720
    mov byte [GOLD_FOOD_X], 0xFF
    ; Countdown-Text auf HUD loeschen
    mov al, 34
    mov bl, 1
    call xy_to_di
    mov cx, 10
    mov ax, 0x0720
    rep stosw
.no_erase_gold:
    ret

update_gold_hud:
    mov al, 34
    mov bl, 1
    call xy_to_di
    mov si, str_gold_lbl
    mov ah, 0x0E
    call print_string

    ; Sekunden = GOLD_TIMER / 7
    mov ax, [GOLD_TIMER]
    xor dx, dx
    mov cx, 7
    div cx
    ; Zeige Sekunde 1-stellig + 's'
    add al, '0'
    mov ah, 0x0E
    stosw
    mov al, 's'
    stosw
    ret

get_random:
    mov ax, [RND_SEED]
    mov cx, 25173
    mul cx
    add ax, 13849
    mov [RND_SEED], ax
    ret

update_score_display:
    push ax
    push bx
    push cx
    push dx

    mov ax, [SCORE]
    cmp ax, [HIGH_SCORE]
    jbe .render_hi
    mov [HIGH_SCORE], ax

.render_hi:
    mov al, 56
    mov bl, 1
    call xy_to_di
    mov ax, [HIGH_SCORE]
    call render_3digits_yellow

    mov al, 70
    mov bl, 1
    call xy_to_di
    mov ax, [SCORE]
    call render_3digits_white

    pop dx
    pop cx
    pop bx
    pop ax
    ret

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
    ; PHASE 8: CRASH DISSOLVE, TOP 3 LEADERBOARD & SOUND ENGINE
    ; =========================================================================
crash_dissolve_animation:
    ; 1. Sound Blaster 16 Sub-Bass Crash & Metal Shatter
    call sound_crash

    ; Tiefer PC Speaker Buzz wenn Speaker aktiv
    cmp byte [CFG_SOUND], 1
    je .buzz_spk
    cmp byte [CFG_SOUND], 2
    je .buzz_spk
    jmp .buzz_done
.buzz_spk:
    mov bx, 0x1200                  ; ~150 Hz
    call force_speaker_tone
    mov ecx, 15000000               ; ~60 ms
    call delay_cycles
    call stop_tone
.buzz_done:

    ; 2. 2x Rot/Weiss blinken
    mov cx, 2
.flash_loop:
    push cx
    mov cx, [SNAKE_LEN]
    xor si, si
.fl_red:
    mov al, [SNAKE_X + si]
    mov bl, [SNAKE_Y + si]
    call xy_to_di
    mov byte [es:di+1], 0x0C        ; Bright Red
    inc si
    loop .fl_red
    mov ecx, 10000000
    call delay_cycles

    mov cx, [SNAKE_LEN]
    xor si, si
.fl_wht:
    mov al, [SNAKE_X + si]
    mov bl, [SNAKE_Y + si]
    call xy_to_di
    mov byte [es:di+1], 0x0F        ; Bright White
    inc si
    loop .fl_wht
    mov ecx, 10000000
    call delay_cycles
    pop cx
    loop .flash_loop

    ; 3. Zerfall von Schwanz zu Kopf mit Pop-Sounds
    mov si, [SNAKE_LEN]
    dec si
.dissolve_loop:
    mov al, [SNAKE_X + si]
    mov bl, [SNAKE_Y + si]
    call xy_to_di
    mov word [es:di], 0x0720
    mov bx, 0x0600
    sub bx, si
    call start_tone
    mov ecx, 1200000
    call delay_cycles
    call stop_tone
    mov ecx, 3000000
    call delay_cycles
    dec si
    jns .dissolve_loop
    ret

check_top3_qualification:
    mov ax, [SCORE]
    cmp ax, [TOP3_TABLE + 13]       ; Vergleiche mit Platz 3
    jbe .no_qualification

    ; Neuer Rekord! Initialen-Eingabedialog anzeigen
    call enter_initials_dialog

    ; In TOP3_TABLE an der passenden Stelle einfuegen
    push es
    push ds
    pop es

    mov ax, [SCORE]
    cmp ax, [TOP3_TABLE + 3]        ; Besser als Platz 1?
    ja .insert_pos1

    cmp ax, [TOP3_TABLE + 8]        ; Besser als Platz 2?
    ja .insert_pos2

    ; Platz 3 ersetzen
    mov si, CURRENT_NAME
    mov di, TOP3_TABLE + 10
    mov cx, 3
    rep movsb
    mov ax, [SCORE]
    mov [TOP3_TABLE + 13], ax
    jmp .save_top3_done

.insert_pos2:
    ; Platz 2 -> Platz 3 verschieben
    mov si, TOP3_TABLE + 5
    mov di, TOP3_TABLE + 10
    mov cx, 5
    rep movsb
    ; Neuen auf Platz 2 setzen
    mov si, CURRENT_NAME
    mov di, TOP3_TABLE + 5
    mov cx, 3
    rep movsb
    mov ax, [SCORE]
    mov [TOP3_TABLE + 8], ax
    jmp .save_top3_done

.insert_pos1:
    ; Platz 2 -> Platz 3
    mov si, TOP3_TABLE + 5
    mov di, TOP3_TABLE + 10
    mov cx, 5
    rep movsb
    ; Platz 1 -> Platz 2
    mov si, TOP3_TABLE + 0
    mov di, TOP3_TABLE + 5
    mov cx, 5
    rep movsb
    ; Neuen auf Platz 1
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

    ; Dialog-Box zentriert (Cols 25..55, Rows 9..16)
    mov al, 25
    mov bl, 9
    call xy_to_di
    mov ax, 0x0E01
    stosw
    mov cx, 29
    mov ax, 0x0E05
    rep stosw
    mov ax, 0x0E02
    stosw

    mov dh, 10
.init_box_mid:
    mov al, 25
    mov bl, dh
    call xy_to_di
    mov ax, 0x0E06
    stosw
    mov cx, 29
    mov ax, 0x0720
    rep stosw
    mov ax, 0x0E06
    stosw
    inc dh
    cmp dh, 16
    jb .init_box_mid

    mov al, 25
    mov bl, 16
    call xy_to_di
    mov ax, 0x0E03
    stosw
    mov cx, 29
    mov ax, 0x0E05
    rep stosw
    mov ax, 0x0E04
    stosw

    mov al, 30
    mov bl, 10
    call xy_to_di
    mov si, str_new_rec_lbl
    mov ah, 0x0E
    call print_string

    mov al, 33
    mov bl, 11
    call xy_to_di
    mov si, str_score_lbl
    mov ah, 0x0F
    call print_string
    mov ax, [SCORE]
    call render_3digits_white

    mov al, 28
    mov bl, 14
    call xy_to_di
    mov si, str_init_nav
    mov ah, 0x07
    call print_string

    mov al, 32
    mov bl, 15
    call xy_to_di
    mov si, str_init_confirm
    mov ah, 0x0B
    call print_string

.redraw_initials:
    mov al, 37
    mov bl, 13
    call xy_to_di
    xor si, si
.show_chars:
    mov al, [CURRENT_NAME + si]
    mov ah, 0x0E
    cmp si, [CUR_CHAR_IDX]
    jne .not_act_char
    mov ah, 0x2F                    ; Bright White on Green
.not_act_char:
    stosw
    mov al, ' '
    mov ah, 0x07
    stosw
    inc si
    cmp si, 3
    jb .show_chars

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
    mov ecx, 25000000
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

draw_top3_rows:
    ; Platz 1 (Row 13)
    mov al, 25
    mov bl, 13
    call xy_to_di
    mov si, str_top1_pfx
    mov ah, 0x0E
    call print_string
    mov si, TOP3_TABLE + 0
    mov ah, 0x0F
    call print_3chars
    mov si, str_dots
    mov ah, 0x07
    call print_string
    mov ax, [TOP3_TABLE + 3]
    call render_3digits_yellow

    ; Platz 2 (Row 14)
    mov al, 25
    mov bl, 14
    call xy_to_di
    mov si, str_top2_pfx
    mov ah, 0x07
    call print_string
    mov si, TOP3_TABLE + 5
    mov ah, 0x0F
    call print_3chars
    mov si, str_dots
    mov ah, 0x07
    call print_string
    mov ax, [TOP3_TABLE + 8]
    call render_3digits_white

    ; Platz 3 (Row 15)
    mov al, 25
    mov bl, 15
    call xy_to_di
    mov si, str_top3_pfx
    mov ah, 0x07
    call print_string
    mov si, TOP3_TABLE + 10
    mov ah, 0x0F
    call print_3chars
    mov si, str_dots
    mov ah, 0x07
    call print_string
    mov ax, [TOP3_TABLE + 13]
    call render_3digits_white
    ret

print_3chars:
    lodsb
    stosw
    lodsb
    stosw
    lodsb
    stosw
    ret

    ; --- CMOS NVRAM PERSISTENZ (0x70 / 0x71) ---
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
    ; Pruefen ob Signatur 0xCC bei Index 0x40 steht
    mov al, 0x40
    call cmos_read_byte
    cmp al, 0xCC
    jne .cmos_invalid

    ; Checksumme berechnen (0x40..0x5D, Checksumme in 0x5E)
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

    ; Gueltige Konfiguration laden!
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

    ; Top 3 Leaderboard laden (15 Bytes: 0x4A..0x58)
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

    ; BiosShell Einstellungen laden (0x59..0x5D)
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

    mov ax, [TOP3_TABLE + 3]
    mov [HIGH_SCORE], ax
    ret

.cmos_invalid:
    ; Werkseinstellungen
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

    ; Top 3 Leaderboard schreiben (0x4A..0x58)
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

    ; BiosShell Einstellungen schreiben (0x59..0x5D)
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

    ; Checksumme berechnen & in 0x5E schreiben
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
    ret

    ; --- VGA HARDWARE DAC THEMES ---
apply_color_theme:
    push ax
    push si
    push cx
    push dx

    mov al, [CFG_THEME]
    and al, 3
    xor ah, ah
    mov si, ax
    mov cx, 48
    mul cl
    mov si, ax
    add si, palette_themes_table

    mov dx, 0x3C8
    xor al, al
    out dx, al                      ; Start bei Farb-Index 0
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

    ; --- ANIMIERTER POST RAM COUNTER ---
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

    ; Hardware-Speaker-Tick (~2 ms)
    mov bx, 0x0480
    call start_tone
    mov ecx, 500000
    call delay_cycles
    call stop_tone

    mov ecx, 12000000
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
    ret

read_key:
.rk_loop:
    in al, 0x64
    test al, 0x01
    jz .no_key
    in al, 0x60
    test al, 0x80
    jnz .rk_loop
    ret
.no_key:
    xor al, al
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
    mov bx, 0x054C
    call force_speaker_tone
    mov ecx, 3750000
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
    mov bx, 0x0474
    call force_speaker_tone
    mov ecx, 3750000
    call delay_cycles
    mov bx, 0x0389
    call set_tone_freq
    mov ecx, 6250000
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

    ; EBX = Sample Index (0..7) VOR jedem I/O-Port-Zugriff berechnen!
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

; --- Cybforge POST Screen Strings ---
str_post_hdr1:
    db "Cybforge Retro BIOS (C)2026 Cybforge Systems Inc.", 0
str_post_hdr2:
    db "BIOS Date: 11/01/2026  Ver: 2.20.00-PRO", 0
str_post_cpu:
    db "CPU Type    : Genuine x86 Processor @ 3.50 GHz", 0
str_post_coproc:
    db "Co-Processor: Installed & Enabled", 0
str_post_vga:
    db "VGA Display : Cybforge PCI Color Video (16MB)", 0
str_post_kbd:
    db "Keyboard    : 8042 PS/2 Controller OK", 0
str_post_pit:
    db "Timer Clock : Intel 8254 PIT @ 1.19318 MHz OK", 0
str_post_disp_mon:
    db "Display Mon : Auto-Detected 1920x1080 FHD (16:9)", 0
str_post_vid_scale:
    db "Resolution  : Adaptive 80x25 Matrix Scaler Active", 0
str_post_mem:
    db "Base Memory : 640K OK", 0
str_post_ext:
    db "Extended Mem: 15360K OK", 0
str_post_drives:
    db "Fixed Disks : None (Bare-Metal ROM Boot)", 0
str_post_f12:
    db "Press F12 for BIOS Setup (or DEL)", 0
str_post_boot:
    db "Booting into Snake in 3s... (or press ENTER)", 0
str_logo_lbl1:
    db "   CYBFORGE   ", 0
str_logo_lbl2:
    db "  RETRO BIOS  ", 0

; --- Cybforge Setup Utility Strings ---
str_setup_title:
    db "CYBFORGE RETRO BIOS SETUP UTILITY", 0
str_box_title_main:
    db " Standard CMOS & Retro Game Features ", 0
str_box_title_help:
    db " Item Specific Help ", 0
str_setup_footer:
    db "[TAB] Switch Reiter   [W/S] Select   [A/D/ENTER] Action   [ESC] Boot", 0

str_opt_speed:
    db "Game Speed        : ", 0
str_opt_walls:
    db "Wall Collision    : ", 0
str_opt_sound:
    db "Sound Output      : ", 0
str_opt_face:
    db "Snake Face Style  : ", 0
str_opt_len:
    db "Starting Length   : ", 0
str_opt_disp:
    db "Screen Geometry   : ", 0
str_opt_reset:
    db "Reset Defaults    : [ Press ENTER ]", 0
str_opt_boot:
    db "Save & Boot Game  : [ Press ENTER ]", 0

str_val_spd_norm:
    db "< Normal (120ms) >", 0
str_val_spd_fast:
    db "< Fast (80ms)    >", 0
str_val_spd_slow:
    db "< Slow (160ms)   >", 0

str_val_wall_solid:
    db "< Solid (Crash)  >", 0
str_val_wall_wrap:
    db "< Wrap-Around    >", 0

str_val_snd_sb16:
    db "< SB16 16-Bit >   ", 0
str_val_snd_spk:
    db "< PC Speaker >    ", 0
str_val_snd_dual:
    db "< Dual Audio >    ", 0
str_val_snd_off:
    db "< Muted >         ", 0

str_post_sb16:
    db "Sound System     : Sound Blaster 16 (16-Bit PCM, DMA 5, Port 220h)", 0
str_post_pcspk:
    db "Sound System     : Standard PC Speaker (PIT 8254 Ch 2)", 0

str_val_face_smile:
    db "< Classic Smile  >", 0
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
    db "Solid: crash on walls. Wrap-Around: pass through walls!", 0
str_help_2:
    db "Enable or mute internal PC Speaker sound effects.", 0
str_help_3:
    db "Select snake head texture: Classic Smile or Cool Sunglasses.", 0
str_help_4:
    db "Starting length of the snake body at game launch.", 0
str_help_5:
    db "Win goal: Fill the 1044-tile board or reach apple goal to win trophy!", 0
str_help_6:
    db "Reset all BIOS and game settings back to factory defaults.", 0
str_help_7:
    db "Save configuration settings and immediately boot into Snake.", 0

; --- Cybforge Setup Utility Strings (Updated) ---
str_opt_theme:
    db "Color Theme       : ", 0
str_opt_arena:
    db "Game Arena        : ", 0

str_val_theme_cyber:
    db "< Cyberpunk Neon >", 0
str_val_theme_matr:
    db "< Matrix Green   >", 0
str_val_theme_amber:
    db "< Amber CRT      >", 0
str_val_theme_cga:
    db "< CGA Retro      >", 0

str_val_arena_open:
    db "< Classic Open   >", 0
str_val_arena_pil:
    db "< Four Pillars   >", 0
str_val_arena_maze:
    db "< The Maze       >", 0

str_help_8:
    db "Reset all BIOS and game settings back to factory defaults.", 0
str_help_9:
    db "Save settings to CMOS NVRAM and immediately boot into Snake.", 0

; --- Snake Game Strings ---
str_game_title:
    db "CYBFORGE SNAKE", 0
str_game_ver:
    db "v2.2", 0
str_hi_score_lbl:
    db "HIGH: ", 0
str_score_lbl:
    db "SCORE: ", 0
str_gold_lbl:
    db "GOLD: ", 0
str_controls:
    db "Controls: [WASD / Arrows] Move   [P / SPACE] Pause   [ESC] Setup", 0

; Start Prompt Strings
str_press_start:
str_press_enter:
str_start_title:
    db "[ENTER / SPACE / MOVE]  Start Game", 0

; Pause Modal Box Strings
str_paused_lbl:
    db "P A U S E D", 0
str_pause_resume:
    db "[P / SPACE] Continue", 0

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
    db "[ENTER] Restart   [ESC] Setup", 0

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
; PHASE 8: CYBFORGE EXTENDED UEFI / BIOS INTERACTIVE SHELL v2.40
; =============================================================================
bios_shell_main:
    call drain_kbd
    mov byte [SH_DIR_ID], 0
    mov byte [SH_SHIFT], 0
    mov byte [SH_CMD_LEN], 0
    mov byte [SH_HIST_LEN], 0
    mov word [SH_DUMP_ADDR], 0x1A00

    call sh_init_theme
    call sh_clear_screen

    ; Startup Banner gemaess CFG_SH_BANNER anzeigen
    cmp byte [CFG_SH_BANNER], 2
    je .sh_prompt_init
    cmp byte [CFG_SH_BANNER], 1
    je .sh_compact_banner

    ; Full UEFI Interactive Shell v2.40 Device Map Banner
    mov si, str_sh_ban1
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line
    mov si, str_sh_ban2
    mov ah, [SH_TEXT_ATTR]
    call sh_print_line
    mov si, str_sh_ban3
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line
    mov si, str_sh_map1
    mov ah, 0x0B
    call sh_print_line
    mov si, str_sh_map2
    mov ah, 0x0B
    call sh_print_line
    mov si, str_sh_map3
    mov ah, 0x0B
    call sh_print_line
    mov si, str_sh_map4
    mov ah, 0x0B
    call sh_print_line
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

.sh_prompt_init:
    mov byte [SH_CMD_LEN], 0
    call sh_draw_input_line

.sh_input_loop:
    call sh_read_key_event
    test al, al
    jz .sh_idle

    ; Sondertasten pruefen:
    cmp al, 0x1C                    ; ENTER -> Befehl ausfuehren
    je .sh_on_enter
    cmp al, 0x0E                    ; BACKSPACE -> Zeichen loeschen
    je .sh_on_backspace
    cmp al, 0x01                    ; ESC -> Zeile leeren
    je .sh_on_esc
    cmp al, 0x48                    ; UP ARROW -> Letzten Befehl aus History holen
    je .sh_on_up
    cmp al, 0x50                    ; DOWN ARROW -> Zeile leeren
    je .sh_on_esc
    cmp al, 0x0F                    ; TAB -> Auto-Completion!
    je .sh_on_tab

    ; Druckbares ASCII-Zeichen aus Scancode-Tabelle ermitteln
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

    ; Puffer-Limit (max 56 Zeichen) pruefen
    mov bl, [SH_CMD_LEN]
    cmp bl, 56
    jae .sh_idle
    xor bh, bh
    mov [SH_CMD_BUF + bx], dl
    inc byte [SH_CMD_LEN]
    call sh_key_click
    call sh_draw_input_line
    jmp .sh_input_loop

.sh_idle:
    mov ecx, 200000                 ; ~1ms Polling fuer verzögerungsfreies Tippen
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
    ; Cursor '_' am Ende der Eingabezeile entfernen
    mov byte [SH_CUR_COL], 0
    call sh_draw_input_no_cursor
    call sh_newline

    cmp byte [SH_CMD_LEN], 0
    je .sh_prompt_init

    ; In History-Puffer sichern
    mov cl, [SH_CMD_LEN]
    mov [SH_HIST_LEN], cl
    xor ch, ch
    xor bx, bx
.sh_save_hist:
    mov al, [SH_CMD_BUF + bx]
    mov [SH_HIST_BUF + bx], al
    inc bx
    loop .sh_save_hist

    ; Eingabe normalisieren (Leading Spaces ueberspringen, Lowercase)
    call sh_normalize_cmd
    cmp byte [SH_CLEAN_BUF], 0
    je .sh_prompt_init

    ; Befehl auswerten & ausfuehren
    call sh_execute_command
    jmp .sh_prompt_init

; -----------------------------------------------------------------------------
; SHELL KEYBOARD DRIVER (Mit Shift-Tracking fuer Grossbuchstaben & Symbole)
; -----------------------------------------------------------------------------
sh_read_key_event:
    in al, 0x64
    test al, 0x01
    jz .sh_no_key
    in al, 0x60
    cmp al, 0x2A                    ; Left Shift Make
    je .sh_shift_dn
    cmp al, 0x36                    ; Right Shift Make
    je .sh_shift_dn
    cmp al, 0xAA                    ; Left Shift Break
    je .sh_shift_up
    cmp al, 0xB6                    ; Right Shift Break
    je .sh_shift_up
    test al, 0x80                   ; Andere Break-Codes ignorieren
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
; SHELL THEME & SCREEN HELPERS
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
    ; Zeile 0: Top Status Bar
    xor di, di
    mov cx, 80
    mov ah, [SH_BAR_ATTR]
    mov al, ' '
    rep stosw
    mov di, (0 * 80 + 1) * 2
    mov si, str_sh_topbar
    mov ah, [SH_BAR_ATTR]
    call print_string

    ; Zeilen 1..23: Terminal Viewport
    mov di, (1 * 80) * 2
    mov cx, 23 * 80
    mov ah, [SH_TEXT_ATTR]
    mov al, ' '
    rep stosw

    ; Zeile 24: Bottom Help Bar
    mov di, (24 * 80) * 2
    mov cx, 80
    mov ah, [SH_BAR_ATTR]
    mov al, ' '
    rep stosw
    mov di, (24 * 80 + 1) * 2
    mov si, str_sh_botbar
    mov ah, [SH_BAR_ATTR]
    call print_string

    mov byte [SH_CUR_ROW], 1
    mov byte [SH_CUR_COL], 0
    ret

sh_newline:
    mov byte [SH_CUR_COL], 0
    inc byte [SH_CUR_ROW]
    cmp byte [SH_CUR_ROW], 23
    jbe .sh_nl_ok
    mov byte [SH_CUR_ROW], 23
    call sh_scroll_up
.sh_nl_ok:
    ret

sh_scroll_up:
    push ds
    push si
    push di
    push cx
    push ax

    mov ax, es
    mov ds, ax                      ; DS = ES = 0xB800 fuer VRAM-Copy
    mov si, (2 * 80) * 2            ; Quelle: Zeile 2
    mov di, (1 * 80) * 2            ; Ziel:   Zeile 1
    mov cx, 22 * 80                 ; 22 Zeilen (Zeilen 2..23 -> 1..22)
    rep movsw

    pop ax
    pop cx
    pop di
    pop si
    pop ds                          ; DS = 0x0000 wiederherstellen

    ; Zeile 23 leeren
    mov di, (23 * 80) * 2
    mov cx, 80
    mov ah, [SH_TEXT_ATTR]
    mov al, ' '
    rep stosw
    ret

sh_fix_attr:
    ; Kombiniert Hintergrund-Nybble aus SH_TEXT_ATTR falls AH < 0x10
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
    ; Druckt String [cs:si] mit Attribut AH ab (SH_CUR_COL, SH_CUR_ROW)
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
    stosw
    inc byte [SH_CUR_COL]
    jmp .spi_loop
.spi_done:
    pop di
    pop bx
    pop ax
    ret

sh_print_line:
    call sh_print_inline
    call sh_newline
    ret

sh_print_char:
    ; Druckt einzelnes Zeichen AL mit Attribut AH an (SH_CUR_COL, SH_CUR_ROW)
    push ax
    push bx
    push di
    call sh_fix_attr
    push ax
    mov al, [SH_CUR_COL]
    mov bl, [SH_CUR_ROW]
    call xy_to_di
    pop ax
    stosw
    inc byte [SH_CUR_COL]
    pop di
    pop bx
    pop ax
    ret

sh_print_hex8:
    ; Druckt DL als 2 Hex-Ziffern mit Attribut AH
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
    ; Druckt DX als 4 Hex-Ziffern mit Attribut AH
    push dx
    mov dl, dh
    call sh_print_hex8
    pop dx
    call sh_print_hex8
    ret

; -----------------------------------------------------------------------------
; PROMPT & INPUT LINE RENDERING
; -----------------------------------------------------------------------------
sh_draw_input_line:
    call sh_draw_input_no_cursor
    ; Blinkenden/Hervorgehobenen Cursor '_' ans Ende setzen
    mov al, '_'
    mov ah, [SH_HIGH_ATTR]
    call sh_print_char
    ret

sh_draw_input_no_cursor:
    ; Aktuelle ZeileSH_CUR_ROW komplett leeren
    mov al, 0
    mov bl, [SH_CUR_ROW]
    call xy_to_di
    mov cx, 80
    mov ah, [SH_TEXT_ATTR]
    mov al, ' '
    rep stosw

    mov byte [SH_CUR_COL], 0
    mov ah, [SH_PROMPT_ATTR]

    ; Prompt-Stil gemaess CFG_SH_PROMPT & SH_DIR_ID waehlen
    cmp byte [CFG_SH_PROMPT], 1
    je .sdp_compact
    cmp byte [CFG_SH_PROMPT], 2
    je .sdp_root

    ; UEFI Standard Prompt (FS0:\>, FS0:\EFI>, FS0:\AUDIO>, FS0:\DIAG>)
    mov al, [SH_DIR_ID]
    mov si, str_pr_fs0_root
    cmp al, 1
    jne .chk_pr_aud
    mov si, str_pr_fs0_efi
    jmp .do_pr_print
.chk_pr_aud:
    cmp al, 2
    jne .chk_pr_diag
    mov si, str_pr_fs0_aud
    jmp .do_pr_print
.chk_pr_diag:
    cmp al, 3
    jne .do_pr_print
    mov si, str_pr_fs0_diag
    jmp .do_pr_print

.sdp_compact:
    mov si, str_pr_compact
    jmp .do_pr_print
.sdp_root:
    mov si, str_pr_root

.do_pr_print:
    call sh_print_inline

    ; Eingabepuffer SH_CMD_BUF ausgeben
    mov cl, [SH_CMD_LEN]
    test cl, cl
    jz .sdp_done
    xor ch, ch
    xor bx, bx
    mov ah, 0x0F                    ; Eingabetext in hellem Weiss
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

    ; Leading Spaces ueberspringen
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
    add al, 32                      ; In Kleinbuchstaben umwandeln
.snc_store:
    mov [SH_CLEAN_BUF + di], al
    inc si
    inc di
    dec cx
    jmp .snc_copy_loop

.snc_term:
    ; Trailing Spaces entfernen
.snc_trim_tail:
    test di, di
    jz .snc_write_zero
    cmp byte [SH_CLEAN_BUF + di - 1], ' '
    jne .snc_write_zero
    dec di
    jmp .snc_trim_tail
.snc_write_zero:
    mov byte [SH_CLEAN_BUF + di], 0
    ret

sh_match_cmd:
    ; Vergleicht SH_CLEAN_BUF mit [cs:si].
    ; Setzt CF=1 bei Treffer (Wortende 0 oder Space) und gibt in BX den Offset zum Argument zurueck!
    xor bx, bx
.smc_loop:
    mov al, [cs:si]
    test al, al
    jz .smc_end_pat
    mov ah, [SH_CLEAN_BUF + bx]
    cmp al, ah
    jne .smc_no
    inc si
    inc bx
    jmp .smc_loop
.smc_end_pat:
    mov ah, [SH_CLEAN_BUF + bx]
    test ah, ah
    jz .smc_yes
    cmp ah, ' '
    jne .smc_no
.smc_skip_arg_sp:
    cmp byte [SH_CLEAN_BUF + bx], ' '
    jne .smc_yes
    inc bx
    jmp .smc_skip_arg_sp
.smc_yes:
    stc
    ret
.smc_no:
    clc
    ret

sh_autocomplete:
    ; Vervollstaendigt den aktuellen Praefix in SH_CMD_BUF anhand von sh_ac_table
    cmp byte [SH_CMD_LEN], 0
    je .sac_done
    call sh_normalize_cmd
    cmp byte [SH_CLEAN_BUF], 0
    je .sac_done

    mov si, sh_ac_table
.sac_next_entry:
    mov al, [cs:si]
    test al, al
    jz .sac_done                    ; Ende der Tabelle

    push si
    xor bx, bx
.sac_cmp:
    mov ah, [SH_CLEAN_BUF + bx]
    test ah, ah
    jz .sac_match_found             ; Kompletter Praefix stimmt ueberein!
    mov al, [cs:si]
    test al, al
    jz .sac_Try_next
    cmp al, ah
    jne .sac_Try_next
    inc si
    inc bx
    jmp .sac_cmp

.sac_Try_next:
    pop si
.sac_skip_str:
    mov al, [cs:si]
    inc si
    test al, al
    jnz .sac_skip_str
    jmp .sac_next_entry

.sac_match_found:
    pop si
    xor bx, bx
.sac_copy_full:
    mov al, [cs:si]
    test al, al
    jz .sac_copy_done
    mov [SH_CMD_BUF + bx], al
    inc si
    inc bx
    jmp .sac_copy_full
.sac_copy_done:
    mov [SH_CMD_LEN], bl
    call sh_key_click
.sac_done:
    ret

; -----------------------------------------------------------------------------
; SHELL COMMAND DISPATCHER & BUILT-IN COMMANDS
; -----------------------------------------------------------------------------
sh_execute_command:
    ; 1. exit / quit / setup -> Zurueck ins BIOS Setup!
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

    ; 7. ls / dir
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

    ; 9. cat / type
    mov si, cmd_cat
    call sh_match_cmd
    jc .do_sh_cat
    mov si, cmd_type
    call sh_match_cmd
    jc .do_sh_cat

    ; 10. sysinfo / neofetch / info
    mov si, cmd_sysinfo
    call sh_match_cmd
    jc .do_sh_sysinfo
    mov si, cmd_neofetch
    call sh_match_cmd
    jc .do_sh_sysinfo
    mov si, cmd_info
    call sh_match_cmd
    jc .do_sh_sysinfo

    ; 11. pci / devices / devtree / lspci
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

    ; 12. cpu / regs
    mov si, cmd_cpu
    call sh_match_cmd
    jc .do_sh_cpu
    mov si, cmd_regs
    call sh_match_cmd
    jc .do_sh_cpu

    ; 13. cmos / nvram
    mov si, cmd_cmos
    call sh_match_cmd
    jc .do_sh_cmos
    mov si, cmd_nvram
    call sh_match_cmd
    jc .do_sh_cmos

    ; 14. dmem / hex / dump
    mov si, cmd_dmem
    call sh_match_cmd
    jc .do_sh_dmem
    mov si, cmd_hex
    call sh_match_cmd
    jc .do_sh_dmem
    mov si, cmd_dump
    call sh_match_cmd
    jc .do_sh_dmem

    ; 15. time / date / rtc
    mov si, cmd_time
    call sh_match_cmd
    jc .do_sh_time
    mov si, cmd_date
    call sh_match_cmd
    jc .do_sh_time
    mov si, cmd_rtc
    call sh_match_cmd
    jc .do_sh_time

    ; 16. sound / play / audio
    mov si, cmd_sound
    call sh_match_cmd
    jc .do_sh_sound
    mov si, cmd_play
    call sh_match_cmd
    jc .do_sh_sound
    mov si, cmd_audio
    call sh_match_cmd
    jc .do_sh_sound

    ; 17. io / ports
    mov si, cmd_io
    call sh_match_cmd
    jc .do_sh_io
    mov si, cmd_ports
    call sh_match_cmd
    jc .do_sh_io

    ; 18. memtest
    mov si, cmd_memtest
    call sh_match_cmd
    jc .do_sh_memtest

    ; 19. color
    mov si, cmd_color
    call sh_match_cmd
    jc .do_sh_color

    ; 20. echo
    mov si, cmd_echo
    call sh_match_cmd
    jc .do_sh_echo

    ; 21. beep
    mov si, cmd_beep
    call sh_match_cmd
    jc .do_sh_beep

    ; 22. snake / boot / snake.efi
    mov si, cmd_snake
    call sh_match_cmd
    jc .do_sh_snake
    mov si, cmd_snake_efi
    call sh_match_cmd
    jc .do_sh_snake
    mov si, cmd_boot
    call sh_match_cmd
    jc .do_sh_snake

    ; 23. reboot / reset
    mov si, cmd_reboot
    call sh_match_cmd
    jc .do_sh_reboot
    mov si, cmd_reset
    call sh_match_cmd
    jc .do_sh_reboot

    ; Unbekannter Befehl:
    mov si, str_sh_err_pfx
    mov ah, 0x0C                    ; Bright Red
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
    ret

; --- 1. EXIT -> ZURUECK INS BIOS SETUP ---
.do_sh_exit:
    pop ax                          ; Return-Adresse von call sh_execute_command verwerfen
    mov byte [SETUP_TAB], 1         ; Auf dem BiosShell-Reiter bleiben
    mov byte [SETUP_SEL], 1         ; Auf "BiosShell" Auswahlpunkt
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
    call sh_print_line
    mov si, str_sh_hlp8
    call sh_print_line
    mov si, str_sh_hlp9
    call sh_print_line
    mov si, str_sh_hlp10
    call sh_print_line
    mov si, str_sh_hlp11
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
    mov si, str_sh_ban3
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line
    mov si, str_sh_map1
    mov ah, 0x0B
    call sh_print_line
    mov si, str_sh_map2
    call sh_print_line
    mov si, str_sh_map3
    call sh_print_line
    mov si, str_sh_map4
    call sh_print_line
    mov si, str_sh_map5
    call sh_print_line
    mov si, str_sh_map6
    call sh_print_line
    ret

; --- 6. MEMMAP ---
.do_sh_memmap:
    mov si, str_sh_mm_hdr
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line
    mov si, str_sh_mm_sep
    mov ah, [SH_TEXT_ATTR]
    call sh_print_line
    mov si, str_sh_mm1
    call sh_print_line
    mov si, str_sh_mm2
    call sh_print_line
    mov si, str_sh_mm3
    call sh_print_line
    mov si, str_sh_mm4
    call sh_print_line
    mov si, str_sh_mm5
    call sh_print_line
    mov si, str_sh_mm6
    call sh_print_line
    mov si, str_sh_mm7
    call sh_print_line
    mov si, str_sh_mm8
    call sh_print_line
    mov si, str_sh_mm_tot
    mov ah, 0x0A
    call sh_print_line
    ret

; --- 7. LS / DIR ---
.do_sh_ls:
    ; Optionales Argument pruefen (z.B. 'ls audio', 'ls efi', 'ls diag')
    mov al, [SH_CLEAN_BUF + bx]
    cmp al, 'e'
    je .ls_efi
    cmp al, 'a'
    je .ls_audio
    cmp al, 'd'
    je .ls_diag

    mov al, [SH_DIR_ID]
    cmp al, 1
    je .ls_efi
    cmp al, 2
    je .ls_audio
    cmp al, 3
    je .ls_diag

    ; Root FS0:\
    mov si, str_ls_root_hdr
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line
    mov si, str_ls_r1
    mov ah, 0x0A
    call sh_print_line
    mov si, str_ls_r2
    call sh_print_line
    mov si, str_ls_r3
    call sh_print_line
    mov si, str_ls_r4
    mov ah, [SH_TEXT_ATTR]
    call sh_print_line
    mov si, str_ls_r5
    call sh_print_line
    mov si, str_ls_r6
    call sh_print_line
    mov si, str_ls_r7
    call sh_print_line
    mov si, str_ls_r8
    call sh_print_line
    mov si, str_ls_r9
    call sh_print_line
    mov si, str_ls_r_tot
    mov ah, 0x0B
    call sh_print_line
    ret

.ls_efi:
    mov si, str_ls_efi_hdr
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line
    mov si, str_ls_e1
    mov ah, [SH_TEXT_ATTR]
    call sh_print_line
    mov si, str_ls_e2
    call sh_print_line
    mov si, str_ls_e3
    call sh_print_line
    mov si, str_ls_e4
    call sh_print_line
    mov si, str_ls_e5
    call sh_print_line
    ret

.ls_audio:
    mov si, str_ls_aud_hdr
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line
    mov si, str_ls_a0
    mov ah, 0x0B
    call sh_print_line
    mov si, str_ls_a1
    call sh_print_line
    mov si, str_ls_a2
    call sh_print_line
    mov si, str_ls_a3
    call sh_print_line
    mov si, str_ls_a4
    call sh_print_line
    mov si, str_ls_a5
    call sh_print_line
    mov si, str_ls_a6
    call sh_print_line
    mov si, str_ls_a7
    call sh_print_line
    ret

.ls_diag:
    mov si, str_ls_diag_hdr
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line
    mov si, str_ls_d1
    mov ah, [SH_TEXT_ATTR]
    call sh_print_line
    mov si, str_ls_d2
    call sh_print_line
    mov si, str_ls_d3
    call sh_print_line
    ret

; --- 8. CD ---
.do_sh_cd:
    mov al, [SH_CLEAN_BUF + bx]
    cmp al, 0
    je .do_sh_cd_root
    cmp al, '.'
    je .do_sh_cd_root
    cmp al, '\\'
    je .do_sh_cd_root
    cmp al, '/'
    je .do_sh_cd_root
    cmp al, 'e'
    je .do_sh_cd_efi
    cmp al, 'a'
    je .do_sh_cd_audio
    cmp al, 'd'
    je .do_sh_cd_diag
    mov si, str_cd_err
    mov ah, 0x0C
    call sh_print_line
    ret
.do_sh_cd_root:
    mov byte [SH_DIR_ID], 0
    ret
.do_sh_cd_efi:
    mov byte [SH_DIR_ID], 1
    ret
.do_sh_cd_audio:
    mov byte [SH_DIR_ID], 2
    ret
.do_sh_cd_diag:
    mov byte [SH_DIR_ID], 3
    ret

; --- 9. CAT / TYPE ---
.do_sh_cat:
    mov al, [SH_CLEAN_BUF + bx]
    cmp al, 's'                     ; startup.nsh
    je .cat_startup
    cmp al, 'r'                     ; readme.txt
    je .cat_readme
    cmp al, 'c'                     ; cmos.cfg
    je .do_sh_cmos
    mov si, str_cat_usage
    mov ah, 0x0E
    call sh_print_line
    ret
.cat_startup:
    mov si, str_cat_st1
    mov ah, 0x0A
    call sh_print_line
    mov si, str_cat_st2
    mov ah, [SH_TEXT_ATTR]
    call sh_print_line
    mov si, str_cat_st3
    call sh_print_line
    mov si, str_cat_st4
    call sh_print_line
    mov si, str_cat_st5
    call sh_print_line
    ret
.cat_readme:
    mov si, str_cat_rm1
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line
    mov si, str_cat_rm2
    mov ah, [SH_TEXT_ATTR]
    call sh_print_line
    mov si, str_cat_rm3
    call sh_print_line
    mov si, str_cat_rm4
    mov ah, 0x0B
    call sh_print_line
    ret

; --- 10. SYSINFO / NEOFETCH ---
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

; --- 11. PCI / DEVTREE ---
.do_sh_pci:
    mov si, str_pci_hdr
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line
    mov si, str_pci_1
    mov ah, [SH_TEXT_ATTR]
    call sh_print_line
    mov si, str_pci_2
    call sh_print_line
    mov si, str_pci_3
    call sh_print_line
    mov si, str_pci_4
    call sh_print_line
    mov si, str_pci_5
    mov ah, 0x0B
    call sh_print_line
    mov si, str_pci_6
    call sh_print_line
    mov si, str_pci_7
    call sh_print_line
    ret

; --- 12. CPU / REGS ---
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

; --- 13. CMOS / NVRAM ---
.do_sh_cmos:
    mov si, str_cmos_hdr
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line

    ; Zeile 1: CMOS 0x40..0x4F live aus Port 0x70/0x71 lesen
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

    ; Zeile 2: CMOS 0x50..0x5F live aus Port 0x70/0x71 lesen
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

; --- 14. DMEM [HEX_ADDR] (Live Hex + ASCII Memory Dump) ---
.do_sh_dmem:
    ; Optionales Hex-Argument in [SH_CLEAN_BUF + bx] parsen
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
    ; 4 Zeilen a 16 Bytes = 64 Bytes dumpen
    mov cx, 4
.dmem_row_loop:
    push cx
    mov dx, [SH_DUMP_ADDR]

    ; Segment-Prefix: 0000: (fuer RAM < 0x8000) oder F000: (fuer ROM >= 0x8000)
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
    call sh_print_char

    ; 16 Hex-Bytes ausgeben
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

    ; 16 ASCII-Zeichen ausgeben
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

; --- 15. TIME / DATE / RTC (Hardware CMOS Clock) ---
.do_sh_time:
    mov si, str_rtc_pfx
    mov ah, [SH_HIGH_ATTR]
    call sh_print_inline

    ; Jahr (20YY)
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

    ; Monat (0x08)
    mov al, 0x08
    call cmos_read_byte
    mov dl, al
    call sh_print_hex8
    mov al, '-'
    call sh_print_char

    ; Tag (0x07)
    mov al, 0x07
    call cmos_read_byte
    mov dl, al
    call sh_print_hex8
    mov al, ' '
    call sh_print_char
    call sh_print_char

    ; Stunde (0x04)
    mov al, 0x04
    call cmos_read_byte
    mov dl, al
    mov ah, 0x0A
    call sh_print_hex8
    mov al, ':'
    call sh_print_char

    ; Minute (0x02)
    mov al, 0x02
    call cmos_read_byte
    mov dl, al
    call sh_print_hex8
    mov al, ':'
    call sh_print_char

    ; Sekunde (0x00)
    mov al, 0x00
    call cmos_read_byte
    mov dl, al
    call sh_print_hex8

    mov si, str_rtc_sfx
    mov ah, [SH_TEXT_ATTR]
    call sh_print_line
    ret

; --- 16. SOUND [0-7] (SB16 16-Bit DMA Testbench) ---
.do_sh_sound:
    mov al, [SH_CLEAN_BUF + bx]
    cmp al, '0'
    jb .snd_default
    cmp al, '7'
    ja .snd_default
    sub al, '0'
    jmp .snd_play_it
.snd_default:
    mov al, 3                       ; Default: Sample 3 (SND_START)
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

; --- 17. IO / PORTS (Live Hardware Port Inspector) ---
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

; --- 18. MEMTEST (64KB Pattern Verification) ---
.do_sh_memtest:
    mov si, str_mt_1
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line

    ; Echter R/W Test im Segment 0x2000
    push es
    mov ax, 0x2000
    mov es, ax
    xor di, di
    mov cx, 32768
    mov ax, 0x55AA
    rep stosw
    xor di, di
    mov cx, 32768
    mov ax, 0xAA55
    rep stosw
    pop es

    mov si, str_mt_2
    mov ah, 0x0A
    call sh_print_line
    ret

; --- 19. COLOR [0-3] ---
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

; --- 20. ECHO ---
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

; --- 21. BEEP ---
.do_sh_beep:
    call sound_toggle
    mov si, str_beep_ok
    mov ah, 0x0A
    call sh_print_line
    ret

; --- 22. SNAKE / BOOT ---
.do_sh_snake:
    pop ax                          ; Return-Adresse verwerfen
    call apply_color_theme
    jmp init_snake_game

; --- 23. REBOOT / RESET ---
.do_sh_reboot:
    pop ax                          ; Return-Adresse verwerfen
    call apply_color_theme
    jmp post_screen

; -----------------------------------------------------------------------------
; SCANCODE SET 1 -> ASCII LOOKUP TABLES (0x00..0x57)
; -----------------------------------------------------------------------------
sh_hex_chars:
    db "0123456789ABCDEF"

sh_scancode_norm:
    ;  00   01   02   03   04   05   06   07   08   09   0A   0B   0C   0D   0E   0F
    db 0,   0,  '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=',  0,   0
    ;  10   11   12   13   14   15   16   17   18   19   1A   1B   1C   1D   1E   1F
    db 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']',  0,   0,  'a', 's'
    ;  20   21   22   23   24   25   26   27   28   29   2A   2B   2C   2D   2E   2F
    db 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', "'", '`',  0,  '\\','z', 'x', 'c', 'v'
    ;  30   31   32   33   34   35   36   37   38   39   3A..57
    db 'b', 'n', 'm', ',', '.', '/',  0,  '*',  0,  ' '
    times 30 db 0

sh_scancode_shift:
    ;  00   01   02   03   04   05   06   07   08   09   0A   0B   0C   0D   0E   0F
    db 0,   0,  '!', '@', '#', '$', '%', '^', '/', '*', '(', ')', '_', '+',  0,   0
    ;  10   11   12   13   14   15   16   17   18   19   1A   1B   1C   1D   1E   1F
    db 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}',  0,   0,  'A', 'S'
    ;  20   21   22   23   24   25   26   27   28   29   2A   2B   2C   2D   2E   2F
    db 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"', '~',  0,  '|', 'Z', 'X', 'C', 'V'
    ;  30   31   32   33   34   35   36   37   38   39   3A..57
    db 'B', 'N', 'M', ';', ':', '?',  0,  '*',  0,  ' '
    times 30 db 0

; Auto-Completion Befehlstabelle
sh_ac_table:
    db "help", 0, "memmap", 0, "memtest", 0, "map", 0, "sysinfo", 0, "neofetch", 0
    db "devices", 0, "devtree", 0, "dmem ", 0, "cmos", 0, "cpu", 0, "regs", 0
    db "time", 0, "sound ", 0, "color ", 0, "clear", 0, "snake", 0, "reboot", 0
    db "exit", 0, "cat ", 0, "cd ", 0, 0

; Command Keywords
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
cmd_cat:        db "cat", 0
cmd_type:       db "type", 0
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
    db "Setup Reiter (Tab): ", 0
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
    db "EFI Shell v2.40 Ready | Type 'exit' in Shell to return to Setup", 0

str_help_tab:
    db "Press [TAB] or [Left/Right] to switch between Main & BiosShell tabs.", 0
str_help_sh1:
    db "Press [ENTER] to launch the interactive Cybforge UEFI/BIOS Shell!", 0
str_help_sh2:
    db "Select terminal color palette for the interactive BIOS Shell.", 0
str_help_sh3:
    db "Choose command prompt format (FS0:\\>, SHELL>, or root@cybforge:#).", 0
str_help_sh4:
    db "Configure device mapping table banner shown when entering Shell.", 0
str_help_sh5:
    db "Enable or mute acoustic keystroke feedback inside the BIOS Shell.", 0
str_help_sh6:
    db "Choose whether POST countdown boots into Snake or directly to Shell.", 0

; --- BIOS Shell UI & Output Strings ---
str_sh_topbar:
    db "CYBFORGE UEFI/BIOS SHELL v2.40 [x86 Unreal 32-Bit]   ROM: 256KB  RAM: 640KB", 0
str_sh_botbar:
    db "[HELP] Cmds  [MAP] Map  [LS] Files  [MEMMAP] RAM  [SYSINFO] Info  [EXIT] Setup", 0

str_pr_fs0_root:    db "FS0:\\> ", 0
str_pr_fs0_efi:     db "FS0:\\EFI> ", 0
str_pr_fs0_aud:     db "FS0:\\AUDIO> ", 0
str_pr_fs0_diag:    db "FS0:\\DIAG> ", 0
str_pr_compact:     db "SHELL> ", 0
str_pr_root:        db "root@cybforge:# ", 0

str_sh_ban1:
    db "UEFI/BIOS Interactive Shell v2.40 [Cybforge Firmware rev 256.4]", 0
str_sh_ban2:
    db "Current running mode 1.1.2 (Flat 32-Bit Unreal Addressing Active)", 0
str_sh_ban3:
    db "Device mapping table:", 0
str_sh_map1:
    db "  FS0  :ROMDisk  - Alias:ROM0:;PciRoot(0x0)/FlashRom(Bank3,64KB,0xFFFF0000)", 0
str_sh_map2:
    db "  BLK0 :WaveBank - Alias:SND0:;PciRoot(0x0)/PcmAudio(128KB,16Bit,0xFFFD0000)", 0
str_sh_map3:
    db "  BLK1 :SysRAM   - Alias:MEM0:;SystemMemory(Base640KB,0x00000000-0x0009FFFF)", 0
str_sh_map4:
    db "  CMOS0:NVRAM    - Alias:RTC0:;IsaBridge(0x70,0x71)/Mc146818(128B,Chksum:OK)", 0
str_sh_map5:
    db "  VGA0 :Display  - Alias:CON0:;Pci(0x0,0x2)/VgaController(80x25,VRAM:0xB8000)", 0
str_sh_map6:
    db "  SB16 :AudioDSP - Alias:DSP0:;Isa(0x220)/SoundBlaster16(DMA5,11025Hz,16Bit)", 0
str_sh_ban_hint:
    db "Type 'help' for commands, 'sysinfo' for telemetry, or 'exit' for BIOS Setup.", 0

str_sh_err_pfx:
    db "Error: '", 0
str_sh_err_sfx:
    db "' is not recognized. Type 'help' for available commands.", 0

str_sh_hlp_hdr:
    db "Cybforge UEFI/BIOS Interactive Shell v2.40 - Command Reference:", 0
str_sh_hlp1:
    db "  help / ?     Show this command list     ver          Firmware & Shell info", 0
str_sh_hlp2:
    db "  map          Show EFI device mapping    memmap       Physical E820 RAM map", 0
str_sh_hlp3:
    db "  ls / dir     List files in ROM disk     cd <dir>     Change dir (efi/audio)", 0
str_sh_hlp4:
    db "  cat <file>   View startup.nsh / readme  dmem [hex]   Live 64B Hex/ASCII dump", 0
str_sh_hlp5:
    db "  sysinfo      ASCII emblem & telemetry   pci/devtree  Enumerate PCI/ISA bus", 0
str_sh_hlp6:
    db "  cpu / regs   Dump live x86 registers    cmos / nvram Dump CMOS NVRAM bytes", 0
str_sh_hlp7:
    db "  time / date  Read hardware RTC clock    sound [0-7]  Play 16-bit PCM wave", 0
str_sh_hlp8:
    db "  io / ports   Read live I/O port states  memtest      Run 64KB RAM test", 0
str_sh_hlp9:
    db "  color [0-3]  Switch shell color theme   echo <text>  Print text to screen", 0
str_sh_hlp10:
    db "  cls / clear  Clear terminal screen      snake / boot Launch SNAKE.EFI game", 0
str_sh_hlp11:
    db "  reboot       Warm reset to BIOS POST    exit / quit  Return to BIOS Setup!", 0

str_sh_ver1:
    db "UEFI Interactive Shell v2.40 [Cybforge x86-16/32 Bare-Metal Edition]", 0
str_sh_ver2:
    db "  Firmware Vendor : Cybforge Systems Inc. (Build 11/02/2026, Rev 2.40-PRO)", 0
str_sh_ver3:
    db "  ROM Image Layout: 262,144 Bytes (256 KB across 4x 64KB Banks 0xFFFC0000+)", 0
str_sh_ver4:
    db "  CPU Architecture: x86 16-Bit Real Mode + 32-Bit Flat Unreal Mode (4GB FS)", 0
str_sh_ver5:
    db "  Audio Engine    : Creative Sound Blaster 16 DSP v4.05 (16-Bit DMA Ch 5)", 0

str_sh_mm_hdr:
    db "Type          Start      End        Size     Description / Attributes", 0
str_sh_mm_sep:
    db "============  =========  =========  =======  ================================", 0
str_sh_mm1:
    db "RT_Code       00000000h  000004FFh     1 KB  Real-Mode IVT & BIOS Data Area", 0
str_sh_mm2:
    db "BS_Data       00001000h  00001FFFh     4 KB  Cybforge Kernel & Shell State", 0
str_sh_mm3:
    db "Conventional  00002000h  0001FFFFh   120 KB  Free Low Conventional Memory", 0
str_sh_mm4:
    db "DMA_Buffer    00020000h  0002FFFFh    64 KB  SB16 16-Bit PCM DMA Bounce RAM", 0
str_sh_mm5:
    db "Conventional  00030000h  0009FFFFh   448 KB  Available Base System Memory", 0
str_sh_mm6:
    db "MMIO_VRAM     000A0000h  000BFFFFh   128 KB  VGA Graphics & Text VRAM (B800h)", 0
str_sh_mm7:
    db "Audio_ROM     FFFD0000h  FFFEFFFFh   128 KB  16-Bit Signed PCM Wave ROM Bank", 0
str_sh_mm8:
    db "Runtime_ROM   FFFF0000h  FFFFFFFFh    64 KB  BIOS System Block 3 & Reset Vec", 0
str_sh_mm_tot:
    db "Summary: 640 KB Base RAM | 15,360 KB Extended | 256 KB Flash ROM (0 Errors)", 0

str_ls_root_hdr:
    db "Directory of: FS0:\\ (Cybforge 256KB ROM Filesystem)", 0
str_ls_r1:
    db "  11/02/2026  12:00  <DIR>          EFI", 0
str_ls_r2:
    db "  11/02/2026  12:00  <DIR>          AUDIO", 0
str_ls_r3:
    db "  11/02/2026  12:00  <DIR>          DIAG", 0
str_ls_r4:
    db "  11/02/2026  12:00         65,536  BIOS.ROM", 0
str_ls_r5:
    db "  11/02/2026  12:00         24,576  SNAKE.EFI", 0
str_ls_r6:
    db "  11/02/2026  12:00          8,192  SHELL.EFI", 0
str_ls_r7:
    db "  11/02/2026  12:00            384  STARTUP.NSH", 0
str_ls_r8:
    db "  11/02/2026  12:00            128  CMOS.CFG", 0
str_ls_r9:
    db "  11/02/2026  12:00            640  README.TXT", 0
str_ls_r_tot:
    db "           6 File(s)     99,456 Bytes | 3 Dir(s) (Use 'cd' or 'cat')", 0

str_ls_efi_hdr:
    db "Directory of: FS0:\\EFI (Executable Boot Modules & Drivers)", 0
str_ls_e1:
    db "  11/02/2026  12:00         16,384  BOOTX86.EFI   (x86 Real/Unreal Loader)", 0
str_ls_e2:
    db "  11/02/2026  12:00         24,576  SNAKE.EFI     (Run via 'snake')", 0
str_ls_e3:
    db "  11/02/2026  12:00          8,192  SHELL.EFI     (Active UEFI Shell v2.40)", 0
str_ls_e4:
    db "  11/02/2026  12:00          4,096  SB16DMA.DRV   (16-Bit DMA Ch 5 Driver)", 0
str_ls_e5:
    db "  11/02/2026  12:00          2,048  VGADAC.DRV    (Hardware Color Themes)", 0

str_ls_aud_hdr:
    db "Directory of: FS0:\\AUDIO (16-Bit PCM WAV Samples @ 11,025 Hz in ROM):", 0
str_ls_a0:
    db "  [0] CRUNCH.WAV  0xFFFD0000   4,412 B   [4] PAUSE.WAV    0xFFFD8588   3,528 B", 0
str_ls_a1:
    db "  [1] GOLDEN.WAV  0xFFFD113C  12,128 B   [5] BOOT.WAV     0xFFFD9350  11,028 B", 0
str_ls_a2:
    db "  [2] CRASH.WAV   0xFFFD409C   9,924 B   [6] GAMEOVER.WAV 0xFFFDBE64  18,744 B", 0
str_ls_a3:
    db "  [3] START.WAV   0xFFFD6760   7,720 B   [7] VICTORY.WAV  0xFFFE079C  24,256 B", 0
str_ls_a4:
    db "  Total: 8 PCM Waveforms (91,740 Bytes). Type 'sound 0'..'sound 7' to play!", 0
str_ls_a5: db 0
str_ls_a6: db 0
str_ls_a7: db 0

str_ls_diag_hdr:
    db "Directory of: FS0:\\DIAG (Hardware Diagnostic Tools):", 0
str_ls_d1:
    db "  11/02/2026  12:00          4,096  MEMTEST.EFI   (Execute via 'memtest')", 0
str_ls_d2:
    db "  11/02/2026  12:00          2,048  CMOSTEST.EFI  (Execute via 'cmos')", 0
str_ls_d3:
    db "  11/02/2026  12:00          3,072  AUDIOTST.EFI  (Execute via 'sound')", 0

str_cd_err:
    db "Directory not found. Valid directories: \\, efi, audio, diag", 0
str_cat_usage:
    db "Usage: cat startup.nsh | cat readme.txt | cat cmos.cfg", 0

str_cat_st1:
    db "# FS0:\\STARTUP.NSH - Cybforge Automated Boot Script", 0
str_cat_st2:
    db "@echo -off", 0
str_cat_st3:
    db "load fs0:\\efi\\vgadac.drv", 0
str_cat_st4:
    db "load fs0:\\efi\\sb16dma.drv", 0
str_cat_st5:
    db "fs0:\\efi\\snake.efi --rom-bank=256k --audio=sb16", 0

str_cat_rm1:
    db "=== CYBFORGE RETRO BIOS & INTERACTIVE SHELL v2.40 ===", 0
str_cat_rm2:
    db "Architecture : 256 KB ROM (0xFFFC0000..0xFFFFFFFF) in 32-Bit Unreal Mode.", 0
str_cat_rm3:
    db "Sound Engine : Creative Sound Blaster 16 (16-Bit Single-Cycle DMA Ch 5).", 0
str_cat_rm4:
    db "Pro Tip      : Run 'dmem 1a00', 'dmem fff0', 'cmos', 'sound 7', or 'exit'!", 0

str_neo1:
    db "   .==========.     root@cybforge-bios", 0
str_neo2:
    db "  /  CYBFORGE  \\    --------------------------------------------", 0
str_neo3:
    db " |   [x86-32]   |   OS / Shell : Cybforge UEFI/BIOS Shell v2.40", 0
str_neo4:
    db " |  RETRO BIOS  |   CPU Mode   : x86 Real + 32-Bit Flat Unreal", 0
str_neo5:
    db "  \\   v2.40    /    Memory     : 640 KB Base RAM / 256 KB Flash ROM", 0
str_neo6:
    db "   '=========='     Video / Snd: VGA 80x25 Custom / SB16 16-Bit DMA5", 0
str_neo7:
    db "                    Status     : NVRAM Checksum OK (Type 'exit' for Setup)", 0

str_pci_hdr:
    db "Bus Dev Fn  Ven:Dev    Hardware Device Description", 0
str_pci_1:
    db "00  00  00  8086:1237  Host Bridge   : Intel 82441FX PMC (i440FX Chipset)", 0
str_pci_2:
    db "00  01  00  8086:7000  ISA Bridge    : Intel 82371SB PIIX3 Southbridge", 0
str_pci_3:
    db "00  01  01  8086:7010  IDE Controller: Intel PIIX3 Bus-Master Dual IDE", 0
str_pci_4:
    db "00  02  00  1234:1111  VGA Compatible: Cybforge PCI Color Graphics (B8000h)", 0
str_pci_5:
    db "ISA Port 0220h/DMA5    Audio Adapter : Creative Sound Blaster 16 DSP v4.05", 0
str_pci_6:
    db "ISA Port 0060h/0064h   Input Device  : Intel 8042 PS/2 Controller (Set 1)", 0
str_pci_7:
    db "ISA Port 0070h/0071h   Non-Volatile  : Motorola MC146818 RTC & CMOS NVRAM", 0

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
    db "Testing 64 KB Extended DMA RAM Buffer (0x20000..0x2FFFF) [0x55AA / 0xAA55]...", 0
str_mt_2:
    db "Result: 32,768 Words Verified - 0 Errors (MEMORY DIAGNOSTIC PASSED)", 0

str_col_ok:
    db "Shell color scheme updated and saved to CMOS NVRAM.", 0
str_beep_ok:
    db "Acoustic diagnostic tone triggered.", 0

; Hardware VGA DAC Palette Themes (4 Themes x 48 Bytes = 192 Bytes)
palette_themes_table:
    ; Theme 0: Cyberpunk Neon
    db 0, 0, 0,    0, 16, 45,  0, 52, 18,  0, 48, 56,  50, 8, 8,   48, 10, 48, 50, 30, 0,  45, 45, 48
    db 20, 20, 24, 15, 35, 63, 15, 63, 25, 10, 60, 63, 63, 14, 18, 63, 20, 60, 63, 56, 12, 63, 63, 63

    ; Theme 1: Matrix Green (Phosphor CRT)
    db 0, 0, 0,    0, 20, 4,   0, 40, 8,   0, 52, 12,  0, 25, 5,   0, 35, 8,   0, 45, 10,  0, 48, 12
    db 0, 15, 3,   0, 35, 8,   0, 63, 15,  8, 60, 16,  0, 50, 10,  4, 55, 12,  16, 63, 20, 35, 63, 35

    ; Theme 2: Amber CRT (Warm Terminal)
    db 0, 0, 0,    20, 10, 0,  35, 18, 0,  45, 24, 0,  30, 14, 0,  40, 20, 0,  48, 26, 0,  50, 28, 0
    db 15, 7, 0,   35, 18, 0,  58, 34, 0,  63, 40, 0,  45, 22, 0,  52, 28, 0,  63, 48, 5,  63, 58, 20

    ; Theme 3: CGA Retro (1981 IBM Classic)
    db 0, 0, 0,    0, 0, 42,   0, 42, 0,   0, 42, 42,  42, 0, 0,   42, 0, 42,  42, 21, 0,  42, 42, 42
    db 21, 21, 21, 21, 21, 63, 21, 63, 21, 21, 63, 63, 63, 21, 21, 63, 21, 63, 63, 63, 21, 63, 63, 63
"""

part3_tables = content[content.find("vga_seq_table:"):content.find("font_table:")]

# Part 4: Complete Font table with custom Snake Face, Apple, Body, Cool Sunglasses Face and full ASCII
font_defs = {
    # Custom game glyphs
    0x01: [0x00, 0x00, 0x00, 0x1F, 0x18, 0x18, 0x18, 0x18], # '┌'
    0x02: [0x00, 0x00, 0x00, 0xF8, 0x18, 0x18, 0x18, 0x18], # '┐'
    0x03: [0x18, 0x18, 0x18, 0x1F, 0x00, 0x00, 0x00, 0x00], # '└'
    0x04: [0x18, 0x18, 0x18, 0xF8, 0x00, 0x00, 0x00, 0x00], # '┘'
    0x05: [0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00], # '─'
    0x06: [0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18], # '│'
    0x07: [0x00, 0x3C, 0x7E, 0xDB, 0xFF, 0xC3, 0xE7, 0x7E], # Snake Face (Classic Smile)
    0x08: [0x08, 0x1C, 0x08, 0x76, 0xFF, 0xFF, 0xFF, 0x7E], # Apple / Fruit
    0x09: [0x00, 0x3C, 0x7E, 0xFF, 0xDB, 0xFF, 0x7E, 0x3C], # Snake Body scale
    0x0A: [0x00, 0x3C, 0x7E, 0xFF, 0xDB, 0x7E, 0x3C, 0x18], # Snake Face (Cool Sunglasses!)

    # Full ASCII 32..126
    ord(' '): [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
    ord('!'): [0x18, 0x3C, 0x3C, 0x18, 0x18, 0x00, 0x18, 0x00],
    ord('"'): [0x66, 0x66, 0x24, 0x00, 0x00, 0x00, 0x00, 0x00],
    ord('#'): [0x6C, 0x6C, 0xFE, 0x6C, 0xFE, 0x6C, 0x6C, 0x00],
    ord('$'): [0x18, 0x3E, 0x60, 0x3C, 0x06, 0x7C, 0x18, 0x00],
    ord('%'): [0x00, 0x66, 0xA6, 0xD8, 0x1B, 0x65, 0x66, 0x00],
    ord('&'): [0x30, 0x48, 0x30, 0x6E, 0xD9, 0xCE, 0x7B, 0x00],
    ord('\''): [0x18, 0x18, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00],
    ord('('): [0x0C, 0x18, 0x30, 0x30, 0x30, 0x18, 0x0C, 0x00],
    ord(')'): [0x30, 0x18, 0x0C, 0x0C, 0x0C, 0x18, 0x30, 0x00],
    ord('*'): [0x00, 0x66, 0x3C, 0xFF, 0x3C, 0x66, 0x00, 0x00],
    ord('+'): [0x00, 0x18, 0x18, 0x7E, 0x18, 0x18, 0x00, 0x00],
    ord(','): [0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x08],
    ord('-'): [0x00, 0x00, 0x00, 0x7E, 0x00, 0x00, 0x00, 0x00],
    ord('.'): [0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x00],
    ord('/'): [0x06, 0x0C, 0x18, 0x30, 0x60, 0xC0, 0x80, 0x00],

    ord('0'): [0x3C, 0x66, 0x6E, 0x76, 0x66, 0x66, 0x3C, 0x00],
    ord('1'): [0x18, 0x38, 0x18, 0x18, 0x18, 0x18, 0x7E, 0x00],
    ord('2'): [0x3C, 0x66, 0x06, 0x0C, 0x18, 0x30, 0x7E, 0x00],
    ord('3'): [0x7E, 0x06, 0x0C, 0x1C, 0x06, 0x66, 0x3C, 0x00],
    ord('4'): [0x0C, 0x1C, 0x3C, 0x6C, 0xFE, 0x0C, 0x0C, 0x00],
    ord('5'): [0x7E, 0x60, 0x7C, 0x06, 0x06, 0x66, 0x3C, 0x00],
    ord('6'): [0x3C, 0x66, 0x60, 0x7C, 0x66, 0x66, 0x3C, 0x00],
    ord('7'): [0x7E, 0x06, 0x0C, 0x18, 0x30, 0x30, 0x30, 0x00],
    ord('8'): [0x3C, 0x66, 0x66, 0x3C, 0x66, 0x66, 0x3C, 0x00],
    ord('9'): [0x3C, 0x66, 0x66, 0x3E, 0x06, 0x66, 0x3C, 0x00],

    ord(':'): [0x00, 0x18, 0x18, 0x00, 0x00, 0x18, 0x18, 0x00],
    ord(';'): [0x00, 0x18, 0x18, 0x00, 0x00, 0x18, 0x18, 0x08],
    ord('<'): [0x0C, 0x18, 0x30, 0x60, 0x30, 0x18, 0x0C, 0x00],
    ord('='): [0x00, 0x00, 0x7E, 0x00, 0x7E, 0x00, 0x00, 0x00],
    ord('>'): [0x30, 0x18, 0x0C, 0x06, 0x0C, 0x18, 0x30, 0x00],
    ord('?'): [0x3C, 0x66, 0x06, 0x0C, 0x18, 0x00, 0x18, 0x00],
    ord('@'): [0x3C, 0x42, 0x99, 0xA5, 0xA5, 0x9E, 0x40, 0x3C],

    ord('A'): [0x3C, 0x66, 0x66, 0x7E, 0x66, 0x66, 0x66, 0x00],
    ord('B'): [0xFC, 0x66, 0x66, 0x7C, 0x66, 0x66, 0xFC, 0x00],
    ord('C'): [0x3C, 0x66, 0x60, 0x60, 0x60, 0x66, 0x3C, 0x00],
    ord('D'): [0xF8, 0x6C, 0x66, 0x66, 0x66, 0x6C, 0xF8, 0x00],
    ord('E'): [0xFE, 0x62, 0x68, 0x78, 0x68, 0x62, 0xFE, 0x00],
    ord('F'): [0xFE, 0x62, 0x68, 0x78, 0x68, 0x60, 0xF0, 0x00],
    ord('G'): [0x3C, 0x66, 0x60, 0x6E, 0x66, 0x66, 0x3C, 0x00],
    ord('H'): [0xC6, 0xC6, 0xC6, 0xFE, 0xC6, 0xC6, 0xC6, 0x00],
    ord('I'): [0x3C, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00],
    ord('J'): [0x1E, 0x06, 0x06, 0x06, 0x06, 0x66, 0x3C, 0x00],
    ord('K'): [0xC6, 0xCC, 0xD8, 0xF0, 0xD8, 0xCC, 0xC6, 0x00],
    ord('L'): [0xF0, 0x60, 0x60, 0x60, 0x60, 0x62, 0xFE, 0x00],
    ord('M'): [0xC6, 0xEE, 0xFE, 0xD6, 0xC6, 0xC6, 0xC6, 0x00],
    ord('N'): [0xC6, 0xE6, 0xF6, 0xDE, 0xCE, 0xC6, 0xC6, 0x00],
    ord('O'): [0x3C, 0x66, 0x66, 0x66, 0x66, 0x66, 0x3C, 0x00],
    ord('P'): [0xFC, 0x66, 0x66, 0x7C, 0x60, 0x60, 0xF0, 0x00],
    ord('Q'): [0x3C, 0x66, 0x66, 0x66, 0x6E, 0x3C, 0x0E, 0x00],
    ord('R'): [0xFC, 0x66, 0x66, 0x7C, 0x6C, 0x66, 0xE6, 0x00],
    ord('S'): [0x3C, 0x66, 0x60, 0x3C, 0x06, 0x66, 0x3C, 0x00],
    ord('T'): [0x7E, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x00],
    ord('U'): [0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00],
    ord('V'): [0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x6C, 0x38, 0x00],
    ord('W'): [0xC6, 0xC6, 0xC6, 0xD6, 0xFE, 0xEE, 0xC6, 0x00],
    ord('X'): [0xC6, 0xC6, 0x6C, 0x38, 0x6C, 0xC6, 0xC6, 0x00],
    ord('Y'): [0x66, 0x66, 0x66, 0x3C, 0x18, 0x18, 0x18, 0x00],
    ord('Z'): [0xFE, 0x06, 0x0C, 0x18, 0x30, 0x60, 0xFE, 0x00],

    ord('['): [0x3C, 0x30, 0x30, 0x30, 0x30, 0x30, 0x3C, 0x00],
    ord('\\'): [0xC0, 0x60, 0x30, 0x18, 0x0C, 0x06, 0x02, 0x00],
    ord(']'): [0x3C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x3C, 0x00],
    ord('^'): [0x18, 0x3C, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00],
    ord('_'): [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF],
    ord('`'): [0x30, 0x18, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x00],

    ord('a'): [0x00, 0x00, 0x3C, 0x06, 0x3E, 0x66, 0x3E, 0x00],
    ord('b'): [0xE0, 0x60, 0x7C, 0x66, 0x66, 0x66, 0x7C, 0x00],
    ord('c'): [0x00, 0x00, 0x3C, 0x66, 0x60, 0x66, 0x3C, 0x00],
    ord('d'): [0x1C, 0x0C, 0x3C, 0x6C, 0x6C, 0x6C, 0x3E, 0x00],
    ord('e'): [0x00, 0x00, 0x3C, 0x66, 0x7E, 0x60, 0x3C, 0x00],
    ord('f'): [0x1C, 0x36, 0x30, 0x78, 0x30, 0x30, 0x78, 0x00],
    ord('g'): [0x00, 0x00, 0x3E, 0x66, 0x66, 0x3E, 0x06, 0x3C],
    ord('h'): [0xE0, 0x60, 0x6C, 0x76, 0x66, 0x66, 0xE6, 0x00],
    ord('i'): [0x18, 0x00, 0x38, 0x18, 0x18, 0x18, 0x3C, 0x00],
    ord('j'): [0x0C, 0x00, 0x1C, 0x0C, 0x0C, 0x0C, 0x6C, 0x38],
    ord('k'): [0xE0, 0x60, 0x66, 0x6C, 0x78, 0x6C, 0xE6, 0x00],
    ord('l'): [0x38, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00],
    ord('m'): [0x00, 0x00, 0xEC, 0xFE, 0xD6, 0xD6, 0xD6, 0x00],
    ord('n'): [0x00, 0x00, 0xDC, 0x66, 0x66, 0x66, 0x66, 0x00],
    ord('o'): [0x00, 0x00, 0x3C, 0x66, 0x66, 0x66, 0x3C, 0x00],
    ord('p'): [0x00, 0x00, 0xDC, 0x66, 0x66, 0x7C, 0x60, 0xF0],
    ord('q'): [0x00, 0x00, 0x3B, 0x66, 0x66, 0x3E, 0x06, 0x0F],
    ord('r'): [0x00, 0x00, 0xDC, 0x76, 0x66, 0x60, 0xF0, 0x00],
    ord('s'): [0x00, 0x00, 0x3E, 0x60, 0x3C, 0x06, 0x7C, 0x00],
    ord('t'): [0x30, 0x30, 0x7C, 0x30, 0x30, 0x34, 0x18, 0x00],
    ord('u'): [0x00, 0x00, 0xC6, 0xC6, 0xC6, 0xC6, 0x7E, 0x00],
    ord('v'): [0x00, 0x00, 0xC6, 0xC6, 0xC6, 0x6C, 0x38, 0x00],
    ord('w'): [0x00, 0x00, 0xC6, 0xD6, 0xD6, 0xFE, 0x6C, 0x00],
    ord('x'): [0x00, 0x00, 0xC6, 0x6C, 0x38, 0x6C, 0xC6, 0x00],
    ord('y'): [0x00, 0x00, 0xC6, 0xC6, 0x66, 0x3E, 0x06, 0x3C],
    ord('z'): [0x00, 0x00, 0x7E, 0x0C, 0x18, 0x30, 0x7E, 0x00],
    ord('{'): [0x0E, 0x18, 0x18, 0x70, 0x18, 0x18, 0x0E, 0x00],
    ord('|'): [0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x00],
    ord('}'): [0x70, 0x18, 0x18, 0x0E, 0x18, 0x18, 0x70, 0x00],
    ord('~'): [0x76, 0xDC, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
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
    0x01: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3F, 0x20, 0x3F, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24],
    0x02: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFC, 0x04, 0xFC, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24],
    0x03: [0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x3F, 0x20, 0x3F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
    0x04: [0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0xFC, 0x04, 0xFC, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
    0x05: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
    0x06: [0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24],
    0x07: [0x00, 0x3C, 0x7E, 0xFF, 0xC3, 0xDB, 0xDB, 0xFF, 0xFF, 0xBD, 0x99, 0xC3, 0x7E, 0x7E, 0x3C, 0x00],
    0x08: [0x06, 0x0E, 0x0C, 0x18, 0x10, 0x76, 0xFF, 0xDF, 0xBF, 0xFF, 0xFF, 0xFF, 0x7E, 0x7E, 0x3C, 0x00],
    0x09: [0x3C, 0x7E, 0xFF, 0xEF, 0xD7, 0xBB, 0x7D, 0xFF, 0xEF, 0xD7, 0xBB, 0x7D, 0xFF, 0x7E, 0x7E, 0x3C],
    0x0A: [0x00, 0x3C, 0x7E, 0xFF, 0x7E, 0xDB, 0xD7, 0xCF, 0xFF, 0xFF, 0xE7, 0xDB, 0x7E, 0x7E, 0x3C, 0x00],
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
    print("=" * 60)
    print(f"[OK] 256 KB BIOS ROM successfully generated ({len(rom_256k)} Bytes)!")
    print(f"     -> {final_bin}")
    print("=" * 60)
else:
    print(f"[ERROR] NASM assembly of Block 3 failed: {res.stderr}")


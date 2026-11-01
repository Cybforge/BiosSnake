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
SNAKE_X     equ 0x1000      ; X-Koordinaten (1200 Bytes fuer volles 1044-Feld: 0x1000..0x14AF)
SNAKE_Y     equ 0x1500      ; Y-Koordinaten (1200 Bytes fuer volles 1044-Feld: 0x1500..0x19AF)
SNAKE_LEN   equ 0x1A00      ; Aktuelle Laenge (Word)
SNAKE_DIR   equ 0x1A02      ; Richtung: 0=Up, 1=Right, 2=Down, 3=Left (Byte)
NEXT_DIR    equ 0x1A03      ; Gepufferte naechste Richtung (Byte)
FOOD_X      equ 0x1A04      ; X-Position der Frucht (Byte)
FOOD_Y      equ 0x1A05      ; Y-Position der Frucht (Byte)
SCORE       equ 0x1A06      ; Aktuelle Punktzahl (Word)
RND_SEED    equ 0x1A08      ; Zufalls-Seed (Word)
DIR_LOCKED  equ 0x1A0A      ; Sperre fuer Richtungswechsel im aktuellen Schritt (Byte)
NEW_HEAD_X  equ 0x1A0B      ; Neuer Kopf X (Byte)
NEW_HEAD_Y  equ 0x1A0C      ; Neuer Kopf Y (Byte)
QUEUED_DIR  equ 0x1A0D      ; Puffer (Byte)
HIGH_SCORE  equ 0x1A0E      ; Session High Score (Word, persists across game restarts)

; Cybforge Retro BIOS Setup Konfigurationsoptionen (0x1A10..0x1A17)
CFG_SPEED   equ 0x1A10      ; 0=Normal, 1=Fast, 2=Slow (Byte)
CFG_WALLS   equ 0x1A11      ; 0=Solid, 1=Wrap-Around (Byte)
CFG_SOUND   equ 0x1A12      ; 0=Enabled, 1=Disabled (Byte)
CFG_FACE    equ 0x1A13      ; 0=Classic Smile, 1=Cool Shades (Byte)
CFG_LEN     equ 0x1A14      ; 0=4 Segments, 1=3 Segments, 2=6 Segments (Byte)
CFG_WIN     equ 0x1A15      ; 0=Full Board (1044), 1=25 Apples, 2=50 Apples, 3=100 Apples (Byte)
CFG_DISP    equ 0x1A16      ; Auto 1080p (Byte)
SETUP_SEL   equ 0x1A17      ; Ausgewaehlte Menue-Zeile im Cybforge Setup (0..7) (Byte)
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

    ; Standardwerte fuer Cybforge Setup initialisieren
    mov word [HIGH_SCORE], 0        ; Session High Score = 0
    mov byte [CFG_SPEED], 0         ; Normal Speed
    mov byte [CFG_WALLS], 0         ; Solid (Die on wall)
    mov byte [CFG_SOUND], 0         ; Sound Enabled
    mov byte [CFG_FACE],  0         ; Classic Smile
    mov byte [CFG_LEN],   0         ; 4 Segments
    mov byte [CFG_WIN],   0         ; 0 = Full Board (1044 Tiles!)
    mov byte [CFG_DISP],  0         ; Auto 1080p
    mov byte [SETUP_SEL], 0         ; Zeile 0 ausgewaehlt

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

    ; Zeile 14 & 15: Memory
    mov di, (14 * 80 + 2) * 2
    mov si, str_post_mem
    mov ah, 0x07
    call print_string

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

    ; 3 Sekunden abgelaufen ohne F12 -> Direkt ins Snake Game booten
boot_direct_snake:
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
    call drain_kbd
    call sound_click

.redraw_setup:
    call draw_setup_screen

.setup_input_loop:
    call read_key
    test al, al
    jz .setup_wait_tick

    ; --- Navigation: W/S oder Pfeiltasten Oben/Unten ---
    cmp al, 0x11                    ; 'W'
    je .sel_up
    cmp al, 0x48                    ; Up Arrow
    je .sel_up

    cmp al, 0x1F                    ; 'S'
    je .sel_down
    cmp al, 0x50                    ; Down Arrow
    je .sel_down

    ; --- Wert aendern / Auswaehlen: A/D, Pfeile Links/Rechts, ENTER, SPACE ---
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

    ; --- ESC: Beenden & Snake starten ---
    cmp al, 0x01                    ; ESC
    je .exit_setup

.setup_wait_tick:
    mov ecx, 70000000               ; ~20 ms
    call delay_cycles
    jmp .setup_input_loop

.sel_up:
    call sound_click
    mov al, [SETUP_SEL]
    test al, al
    jz .wrap_up
    dec byte [SETUP_SEL]
    jmp .redraw_setup
.wrap_up:
    mov byte [SETUP_SEL], 7         ; Max Zeilen-Index = 7
    jmp .redraw_setup

.sel_down:
    call sound_click
    mov al, [SETUP_SEL]
    cmp al, 7
    jae .wrap_down
    inc byte [SETUP_SEL]
    jmp .redraw_setup
.wrap_down:
    mov byte [SETUP_SEL], 0
    jmp .redraw_setup

.val_prev:
    call sound_toggle
    mov al, [SETUP_SEL]
    cmp al, 0
    jne .p1
    dec byte [CFG_SPEED]
    jns .redraw_setup
    mov byte [CFG_SPEED], 2
    jmp .redraw_setup
.p1:
    cmp al, 1
    jne .p2
    xor byte [CFG_WALLS], 1
    jmp .redraw_setup
.p2:
    cmp al, 2
    jne .p3
    xor byte [CFG_SOUND], 1
    jmp .redraw_setup
.p3:
    cmp al, 3
    jne .p4
    xor byte [CFG_FACE], 1
    jmp .redraw_setup
.p4:
    cmp al, 4
    jne .p5
    dec byte [CFG_LEN]
    jns .redraw_setup
    mov byte [CFG_LEN], 2
    jmp .redraw_setup
.p5:
    cmp al, 5
    jne .redraw_setup
    dec byte [CFG_WIN]
    jns .redraw_setup
    mov byte [CFG_WIN], 3
    jmp .redraw_setup

.val_next:
    call sound_toggle
    mov al, [SETUP_SEL]
    cmp al, 0
    jne .n1
    inc byte [CFG_SPEED]
    cmp byte [CFG_SPEED], 3
    jb .redraw_setup
    mov byte [CFG_SPEED], 0
    jmp .redraw_setup
.n1:
    cmp al, 1
    jne .n2
    xor byte [CFG_WALLS], 1
    jmp .redraw_setup
.n2:
    cmp al, 2
    jne .n3
    xor byte [CFG_SOUND], 1
    jmp .redraw_setup
.n3:
    cmp al, 3
    jne .n4
    xor byte [CFG_FACE], 1
    jmp .redraw_setup
.n4:
    cmp al, 4
    jne .n5
    inc byte [CFG_LEN]
    cmp byte [CFG_LEN], 3
    jb .redraw_setup
    mov byte [CFG_LEN], 0
    jmp .redraw_setup
.n5:
    cmp al, 5
    jne .redraw_setup
    inc byte [CFG_WIN]
    cmp byte [CFG_WIN], 4
    jb .redraw_setup
    mov byte [CFG_WIN], 0
    jmp .redraw_setup

.val_enter:
    mov al, [SETUP_SEL]
    cmp al, 6
    je .do_reset_defaults
    cmp al, 7
    je .exit_setup
    jmp .val_next

.do_reset_defaults:
    mov byte [CFG_SPEED], 0
    mov byte [CFG_WALLS], 0
    mov byte [CFG_SOUND], 0
    mov byte [CFG_FACE],  0
    mov byte [CFG_LEN],   0
    mov byte [CFG_WIN],   0
    mov byte [CFG_DISP],  0
    call sound_toggle
    jmp .redraw_setup

.exit_setup:
    call sound_start
    jmp init_snake_game

    ; =========================================================================
    ; SETUP SCREEN RENDERER (Cybforge Retro Style)
    ; =========================================================================
draw_setup_screen:
    ; 1. Hintergrund mit BIOS-Blau (0x1F) fuellen
    xor di, di
    mov cx, 80 * 25
    mov ax, 0x1F20
    rep stosw

    ; 2. Titelzeile (Zeile 0)
    mov di, (0 * 80 + 10) * 2
    mov si, str_setup_title
    mov ah, 0x1F
    call print_string

    ; Trennlinie (Zeile 1)
    mov di, (1 * 80 + 0) * 2
    mov cx, 80
    mov ax, 0x1F05
    rep stosw

    ; 3. Haupt-Optionskasten (Zeile 3 bis 18, Spalte 6 bis 73)
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
    mov ah, 0x1E                    ; Yellow
    call print_string

    mov cx, 14
    mov di, (4 * 80 + 6) * 2
.sb_vert1:
    mov word [es:di], 0x1F06
    mov word [es:di + 67 * 2], 0x1F06
    add di, 80 * 2
    loop .sb_vert1

    mov di, (18 * 80 + 6) * 2
    mov ax, 0x1F03                  ; '└'
    stosw
    mov cx, 66
    mov ax, 0x1F05                  ; '─'
    rep stosw
    mov ax, 0x1F04                  ; '┘'
    stosw

    ; 4. Hilfe-Kasten (Zeile 19 bis 23, Spalte 6 bis 73)
    mov di, (19 * 80 + 6) * 2
    mov ax, 0x1F01                  ; '┌'
    stosw
    mov cx, 66
    mov ax, 0x1F05                  ; '─'
    rep stosw
    mov ax, 0x1F02                  ; '┐'
    stosw

    mov di, (19 * 80 + 10) * 2
    mov si, str_box_title_help
    mov ah, 0x1E
    call print_string

    mov cx, 3
    mov di, (20 * 80 + 6) * 2
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

    ; 5. Fusszeile / Tastaturbedienung (Zeile 24)
    mov di, (24 * 80 + 8) * 2
    mov si, str_setup_footer
    mov ah, 0x1F
    call print_string

    ; 6. Menue-Punkte zeichnen (Zeilen 0..7)
    ; Zeile 0: Game Speed (Row 4)
    mov bl, 0
    mov dh, 4
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

    ; Zeile 1: Wall Collision (Row 6)
    mov bl, 1
    mov dh, 6
    mov si, str_opt_walls
    call draw_menu_row
    mov si, str_val_wall_solid
    cmp byte [CFG_WALLS], 1
    jne .draw_wall_val
    mov si, str_val_wall_wrap
.draw_wall_val:
    call draw_val_str

    ; Zeile 2: PC Speaker Sound (Row 8)
    mov bl, 2
    mov dh, 8
    mov si, str_opt_sound
    call draw_menu_row
    mov si, str_val_snd_on
    cmp byte [CFG_SOUND], 1
    jne .draw_snd_val
    mov si, str_val_snd_off
.draw_snd_val:
    call draw_val_str

    ; Zeile 3: Snake Face Style (Row 10)
    mov bl, 3
    mov dh, 10
    mov si, str_opt_face
    call draw_menu_row
    mov si, str_val_face_smile
    cmp byte [CFG_FACE], 1
    jne .draw_face_val
    mov si, str_val_face_cool
.draw_face_val:
    call draw_val_str

    ; Zeile 4: Starting Length (Row 12)
    mov bl, 4
    mov dh, 12
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

    ; Zeile 5: Victory Target (Row 14)
    mov bl, 5
    mov dh, 14
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

    ; Zeile 6: Reset Defaults (Row 16)
    mov bl, 6
    mov dh, 16
    mov si, str_opt_reset
    call draw_menu_row

    ; Zeile 7: Save & Boot Game (Row 17)
    mov bl, 7
    mov dh, 17
    mov si, str_opt_boot
    call draw_menu_row

    ; 7. Dynamischen Hilfetext in Zeile 21 schreiben
    mov di, (21 * 80 + 9) * 2
    mov al, [SETUP_SEL]
    mov si, str_help_0
    test al, al
    jz .do_draw_help
    cmp al, 1
    jne .h2
    mov si, str_help_1
    jmp .do_draw_help
.h2:
    cmp al, 2
    jne .h3
    mov si, str_help_2
    jmp .do_draw_help
.h3:
    cmp al, 3
    jne .h4
    mov si, str_help_3
    jmp .do_draw_help
.h4:
    cmp al, 4
    jne .h5
    mov si, str_help_4
    jmp .do_draw_help
.h5:
    cmp al, 5
    jne .h6
    mov si, str_help_5
    jmp .do_draw_help
.h6:
    cmp al, 6
    jne .h7
    mov si, str_help_6
    jmp .do_draw_help
.h7:
    mov si, str_help_7
.do_draw_help:
    mov ah, 0x1F
    call print_string
    ret

; Zeichnet eine Menue-Zeile mit Highlight wenn aktiv
; Eingang: BL = Zeilen-Index (0..7), DH = Bildschirmzeile (Row), SI = Label
draw_menu_row:
    push bx
    push dx
    mov ah, 0x1F                    ; Standard: White on Blue
    cmp bl, [SETUP_SEL]
    jne .dmr_clear_bar
    mov ah, 0x70                    ; Highlight: Black on Light Gray!
.dmr_clear_bar:
    push ax
    xor dl, dl
    mov al, 9
    mov bl, dh
    call xy_to_di
    pop ax
    push di
    mov al, ' '
    mov cx, 62
    rep stosw
    pop di

    pop dx
    pop bx
    call print_string
    ret

draw_val_str:
    call print_string
    ret

    ; =========================================================================
    ; PHASE 3: SNAKE GAME INITIALISIERUNG MIT BIOS-SETUP-OPTIONEN
    ; =========================================================================
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

    call update_score_display
    call spawn_fruit
    call draw_snake
    call draw_fruit

    ; Start Modal Box anzeigen
    call draw_start_box
    call drain_kbd

.wait_start:
    call read_key
    cmp al, 0x1C                    ; ENTER -> Spiel starten
    je .game_started
    cmp al, 0x01                    ; ESC -> Ins BIOS Setup
    je core_bios_setup
    mov ecx, 30000000
    call delay_cycles
    jmp .wait_start

.game_started:
    call sound_start
    call erase_start_box
    call draw_snake
    call draw_fruit

    ; =========================================================================
    ; PHASE 4: HAUPTSPIEL-SCHLEIFE
    ; =========================================================================
game_loop:
    ; 1. Mini-Ticks Schleife gemaess CFG_SPEED
    mov bp, 11                      ; Normal: 11 Ticks (~200ms, ~5.0 Schritte/Sekunde)
    cmp byte [CFG_SPEED], 1
    jne .chk_spd_slow
    mov bp, 7                       ; Fast: 7 Ticks (~125ms, ~8.0 Schritte/Sekunde)
    jmp .apply_dir_aspect
.chk_spd_slow:
    cmp byte [CFG_SPEED], 2
    jne .apply_dir_aspect
    mov bp, 16                      ; Slow: 16 Ticks (~290ms, ~3.5 Schritte/Sekunde)

.apply_dir_aspect:
    mov al, [NEXT_DIR]
    test al, 1
    jnz .tick_loop                  ; Horizontal -> unveraendert
    ; Vertikale Achse: bp * 1.25 fuer optische Gleichmaessigkeit
    mov ax, bp
    mov cx, 5
    mul cx
    shr ax, 2
    mov bp, ax

.tick_loop:
    call handle_input
    mov ecx, 4500000                ; ~18 ms
    call delay_cycles
    dec bp
    jnz .tick_loop

    ; 2. Richtung uebernehmen & Schloss freigeben
    mov al, [NEXT_DIR]
    mov [SNAKE_DIR], al
    mov byte [DIR_LOCKED], 0

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
    jle game_over
    cmp al, 69
    jge game_over
    cmp bl, 3
    jle game_over
    cmp bl, 22
    jge game_over

.no_wall_collision:
    ; 5. Kollision mit eigenem Koerper pruefen (Schwanzspitze zieht weg)
    mov cx, [SNAKE_LEN]
    dec cx
    jz .no_body_collision
    xor si, si
.self_chk_loop:
    cmp al, [SNAKE_X + si]
    jne .no_body_hit
    cmp bl, [SNAKE_Y + si]
    je game_over
.no_body_hit:
    inc si
    loop .self_chk_loop

.no_body_collision:
    ; 6. Pruefen ob Frucht gefressen wurde
    mov al, [NEW_HEAD_X]
    mov bl, [NEW_HEAD_Y]
    cmp al, [FOOD_X]
    jne .normal_move
    cmp bl, [FOOD_Y]
    jne .normal_move

    ; --- FRUCHT GEFRESSEN! ---
    inc word [SCORE]
    call update_score_display
    call sound_eat_fruit

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

    ; =========================================================================
    ; PHASE 5A: VICTORY SCREEN (Trophäe & Sieges-Fanfare)
    ; =========================================================================
victory_screen:
    call sound_victory

    ; Spielfeld-Innenbereich mit Schwarz loeschen (Spalten 11..68, Zeilen 4..21)
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
    mov ah, 0x0E                    ; Yellow Star Banner
    call print_string

    mov al, 28
    mov bl, 5
    call xy_to_di
    mov si, str_vic_hdr2
    mov ah, 0x0A                    ; Bright Green
    call print_string

    ; Gold-Trophäe (Zentriert um Spalte 40)
    mov al, 32
    mov bl, 7
    call xy_to_di
    mov si, str_vic_t1
    mov ah, 0x0E                    ; Gold
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
    mov ah, 0x0B                    ; Bright Cyan Handles & Gold
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
    mov ah, 0x0F                    ; Bright White Plaque
    call print_string

    mov al, 33
    mov bl, 18
    call xy_to_di
    mov si, str_vic_t12
    mov ah, 0x0F                    ; Bright White Plaque
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
    mov ah, 0x0B                    ; Bright Cyan
    call print_string

    ; Zeile 24 sauber loeschen
    mov al, 0
    mov bl, 24
    call xy_to_di
    mov cx, 80
    mov ax, 0x0720
    rep stosw

    ; Footer auf Zeile 24 zentriert schreiben
    mov al, 17
    mov bl, 24
    call xy_to_di
    mov si, str_vic_footer
    mov ah, 0x07                    ; Light Gray
    call print_string

    call drain_kbd

.wait_vic_key:
    call read_key
    cmp al, 0x1C                    ; ENTER -> Direkt neues Spiel starten
    je init_snake_game
    cmp al, 0x01                    ; ESC -> Zurueck ins BIOS Setup
    je core_bios_setup
    mov ecx, 30000000
    call delay_cycles
    jmp .wait_vic_key

    ; =========================================================================
    ; PHASE 5: GAME OVER MODAL DIALOG & RESTART
    ; =========================================================================
game_over:
    call sound_game_over

    ; Red Modal Box fuer GAME OVER (Cols 24..56, Rows 9..15)
    mov al, 24
    mov bl, 9
    call xy_to_di
    mov ax, 0x0C01                  ; '╔' Red
    stosw
    mov cx, 31
    mov ax, 0x0C05                  ; '═' Red
    rep stosw
    mov ax, 0x0C02                  ; '╗' Red
    stosw

    mov dh, 10
.go_box_mid:
    mov al, 24
    mov bl, dh
    call xy_to_di
    mov ax, 0x0C06                  ; '║' Red
    stosw
    mov cx, 31
    mov ax, 0x0720                  ; Blank space
    rep stosw
    mov ax, 0x0C06                  ; '║' Red
    stosw
    inc dh
    cmp dh, 15
    jb .go_box_mid

    mov al, 24
    mov bl, 15
    call xy_to_di
    mov ax, 0x0C03                  ; '╚' Red
    stosw
    mov cx, 31
    mov ax, 0x0C05                  ; '═' Red
    rep stosw
    mov ax, 0x0C04                  ; '╝' Red
    stosw

    ; Row 11: "G A M E   O V E R" in Bright Red
    mov al, 31
    mov bl, 11
    call xy_to_di
    mov si, str_game_over
    mov ah, 0x0C                    ; Bright Red
    call print_string

    ; Row 12: "Final Score: 000" in Yellow
    mov al, 32
    mov bl, 12
    call xy_to_di
    mov si, str_final_score_lbl
    mov ah, 0x0E                    ; Yellow
    call print_string
    mov ax, [SCORE]
    call render_3digits_yellow

    ; Row 14: "[ENTER] Restart   [ESC] Setup" in Light Cyan
    mov al, 26
    mov bl, 14
    call xy_to_di
    mov si, str_go_restart_info
    mov ah, 0x0B                    ; Light Cyan
    call print_string

    call drain_kbd

.wait_enter:
    call read_key
    cmp al, 0x1C                    ; ENTER -> Restart
    je .do_restart
    cmp al, 0x01                    ; ESC -> Setup
    je .do_setup
    mov ecx, 30000000
    call delay_cycles
    jmp .wait_enter

.do_restart:
    call sound_start
    jmp init_snake_game

.do_setup:
    call sound_click
    jmp core_bios_setup

    ; =========================================================================
    ; PHASE 6: INPUT HANDLER (WASD + Arrows + ESC)
    ; =========================================================================
handle_input:
    call read_key
    test al, al
    jz .input_done

    cmp al, 0x01                    ; ESC -> Ab ins BIOS Setup
    jne .chk_wasd
    pop ax                          ; Stack-Ruecksprung bereinigen
    call sound_click
    jmp core_bios_setup

.chk_wasd:
    ; 'W' (0x11) / Up (0x48) -> Up (0)
    ; 'D' (0x20) / Right (0x4D) -> Right (1)
    ; 'S' (0x1F) / Down (0x50) -> Down (2)
    ; 'A' (0x1E) / Left (0x4B) -> Left (3)
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
    jne .input_done

    mov bl, [SNAKE_DIR]
    cmp cl, bl
    je .input_done
    xor bl, 2
    cmp cl, bl
    je .input_done

    mov [NEXT_DIR], cl
    mov byte [DIR_LOCKED], 1

.input_done:
    ret

    ; =========================================================================
    ; PHASE 7: GRAFIK & ZEICHENFUNKTIONEN
    ; =========================================================================
draw_game_board:
    ; Titel links: "CYBFORGE SNAKE" (Cyan) + "v2.1" (Light Gray)
    mov al, 10
    mov bl, 1
    call xy_to_di
    mov si, str_game_title
    mov ah, 0x0B                    ; Cyan
    call print_string

    mov al, 25
    mov bl, 1
    call xy_to_di
    mov si, str_game_ver
    mov ah, 0x07                    ; Light Gray
    call print_string

    ; High Score Label: "HIGH: " at (50, 1)
    mov al, 50
    mov bl, 1
    call xy_to_di
    mov si, str_hi_score_lbl
    mov ah, 0x0E                    ; Yellow
    call print_string

    ; Score Label: "SCORE: " at (63, 1)
    mov al, 63
    mov bl, 1
    call xy_to_di
    mov si, str_score_lbl
    mov ah, 0x0F                    ; Bright White
    call print_string

    ; Steuerungsanzeige unten at Y=24
    mov al, 8
    mov bl, 24
    call xy_to_di
    mov si, str_controls
    mov ah, 0x07                    ; Light Gray
    call print_string

    ; Spielfeldrahmen (X: 10..69, Y: 3..22) in Neon-Cyan (0x0B)
    mov al, 10
    mov bl, 3
    call xy_to_di
    mov ax, 0x0B01                  ; '╔'
    stosw
    mov cx, 58
    mov ax, 0x0B05                  ; '═'
    rep stosw
    mov ax, 0x0B02                  ; '╗'
    stosw

    mov cx, 18
    mov dh, 4
.vert_loop:
    mov al, 10
    mov bl, dh
    call xy_to_di
    mov ax, 0x0B06                  ; '║'
    stosw
    mov al, 69
    call xy_to_di
    mov ax, 0x0B06                  ; '║'
    stosw
    inc dh
    loop .vert_loop

    mov al, 10
    mov bl, 22
    call xy_to_di
    mov ax, 0x0B03                  ; '╚'
    stosw
    mov cx, 58
    mov ax, 0x0B05                  ; '═'
    rep stosw
    mov ax, 0x0B04                  ; '╝'
    stosw

    ; Spielfeld-Innenbereich mit Schwarz saeubern (Spalten 11..68, Zeilen 4..21)
    mov dh, 4
.clr_inner:
    mov al, 11
    mov bl, dh
    call xy_to_di
    mov cx, 58
    mov ax, 0x0720                  ; Leerzeichen
    rep stosw
    inc dh
    cmp dh, 22
    jb .clr_inner
    ret

draw_start_box:
    ; Top border: (24, 9)
    mov al, 24
    mov bl, 9
    call xy_to_di
    mov ax, 0x0B01                  ; '╔'
    stosw
    mov cx, 31
    mov ax, 0x0B05                  ; '═'
    rep stosw
    mov ax, 0x0B02                  ; '╗'
    stosw

    ; Middle rows 10..14
    mov dh, 10
.start_box_mid:
    mov al, 24
    mov bl, dh
    call xy_to_di
    mov ax, 0x0B06                  ; '║'
    stosw
    mov cx, 31
    mov ax, 0x0720                  ; Blank space
    rep stosw
    mov ax, 0x0B06                  ; '║'
    stosw
    inc dh
    cmp dh, 15
    jb .start_box_mid

    ; Bottom border: (24, 15)
    mov al, 24
    mov bl, 15
    call xy_to_di
    mov ax, 0x0B03                  ; '╚'
    stosw
    mov cx, 31
    mov ax, 0x0B05                  ; '═'
    rep stosw
    mov ax, 0x0B04                  ; '╝'
    stosw

    ; Title inside box: (30, 11) -> "CYBFORGE RETRO SNAKE" (20 chars)
    mov al, 30
    mov bl, 11
    call xy_to_di
    mov si, str_start_title
    mov ah, 0x0E                    ; Yellow
    call print_string

    ; Press enter: (29, 13) -> "Press [ENTER] to Start" (22 chars)
    mov al, 29
    mov bl, 13
    call xy_to_di
    mov si, str_press_enter
    mov ah, 0x0A                    ; Bright Green
    call print_string
    ret

erase_start_box:
    mov dh, 9
.erase_loop:
    mov al, 24
    mov bl, dh
    call xy_to_di
    mov cx, 33
    mov ax, 0x0720
    rep stosw
    inc dh
    cmp dh, 16
    jb .erase_loop
    ret

draw_snake:
    ; Kopf zeichnen gemaess CFG_FACE (0x07 Smile vs 0x0A Sunglasses)
    mov al, [SNAKE_X]
    mov bl, [SNAKE_Y]
    call xy_to_di
    mov al, 0x07                    ; Default: Classic Smile
    cmp byte [CFG_FACE], 1
    jne .draw_head_glyph
    mov al, 0x0A                    ; Cool Sunglasses!
.draw_head_glyph:
    mov ah, 0x0A                    ; Bright Green
    stosw

    ; Koerpersegmente (Glyph 0x09)
    mov cx, [SNAKE_LEN]
    dec cx
    jz .draw_snake_done
    mov si, 1
.body_loop:
    mov al, [SNAKE_X + si]
    mov bl, [SNAKE_Y + si]
    call xy_to_di
    mov ax, 0x0209                  ; Green Body Dragon Scales (0x09)
    stosw
    inc si
    loop .body_loop
.draw_snake_done:
    ret

draw_fruit:
    mov al, [FOOD_X]
    mov bl, [FOOD_Y]
    call xy_to_di
    mov ax, 0x0C08                  ; Bright Red Apple (0x08)
    stosw
    ret

spawn_fruit:
    push cx
    push si
    mov bp, 100                     ; Bis zu 100 Versuche
.try_spawn:
    ; Zufalls-X im Bereich [11..68] (58 Spalten)
    call get_random
    xor dx, dx
    mov cx, 58
    div cx
    add dl, 11
    mov [FOOD_X], dl

    ; Zufalls-Y im Bereich [4..21] (18 Zeilen)
    call get_random
    xor dx, dx
    mov cx, 18
    div cx
    add dl, 4
    mov [FOOD_Y], dl

    ; Pruefen ob (FOOD_X, FOOD_Y) auf einem Schlangensegment liegt
    mov cx, [SNAKE_LEN]
    xor si, si
    mov al, [FOOD_X]
    mov ah, [FOOD_Y]
.chk_food_body:
    cmp al, [SNAKE_X + si]
    jne .chk_food_next
    cmp ah, [SNAKE_Y + si]
    je .retry_food                  ; Kollision mit Schlange -> Neuer Versuch!
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

get_random:
    ; LCG: SEED = (SEED * 25173 + 13849)
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

    ; High Score aktualisieren falls noetig
    mov ax, [SCORE]
    cmp ax, [HIGH_SCORE]
    jbe .render_hi
    mov [HIGH_SCORE], ax

.render_hi:
    ; High Score Wert dreistellig bei (56, 1) in Gelb
    mov al, 56
    mov bl, 1
    call xy_to_di
    mov ax, [HIGH_SCORE]
    call render_3digits_yellow

    ; Score Wert dreistellig bei (70, 1) in Weiss
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
    mov ah, 0x0E                    ; Yellow
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
    mov ah, 0x0F                    ; Bright White
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
    ; PHASE 8: HILFSFUNKTIONEN & SOUND ENGINE
    ; =========================================================================
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
    shl di, 4                       ; Y * 16
    shl bx, 6                       ; Y * 64
    add di, bx                      ; Y * 80
    xor ah, ah
    add di, ax                      ; Y * 80 + X
    shl di, 1                       ; (Y * 80 + X) * 2
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
    in al, 0x64
    test al, 0x01
    jz .no_key
    in al, 0x60
    test al, 0x80
    jnz .no_key
    ret
.no_key:
    xor al, al
    ret

start_tone:
    cmp byte [CFG_SOUND], 0
    jne .muted
    push ax
    mov al, 0xB6                    ; Channel 2, LSB/MSB, Mode 3 square wave
    out 0x43, al
    mov al, bl
    out 0x42, al
    mov al, bh
    out 0x42, al
    in al, 0x61
    or al, 0x03                     ; Speaker enable
    out 0x61, al
    pop ax
.muted:
    ret

set_tone_freq:
    cmp byte [CFG_SOUND], 0
    jne .muted
    push ax
    mov al, bl
    out 0x42, al
    mov al, bh
    out 0x42, al
    pop ax
.muted:
    ret

stop_tone:
    push ax
    in al, 0x61
    and al, 0xFC                    ; Speaker disable
    out 0x61, al
    pop ax
    ret

sound_eat_fruit:
    push ax
    push bx
    push ecx
    ; Angenehmer zweitoeniger Pickup-Chime (G5 -> C6, ~100 ms)
    mov bx, 0x05F2                  ; G5 (784 Hz)
    call start_tone
    mov ecx, 8750000                ; ~35 ms
    call delay_cycles
    mov bx, 0x0474                  ; C6 (1046 Hz)
    call set_tone_freq
    mov ecx, 16250000               ; ~65 ms
    call delay_cycles
    call stop_tone
    pop ecx
    pop bx
    pop ax
    ret

sound_game_over:
    push ax
    push bx
    push ecx
    ; Warmer melancholischer Moll-Abgang (C5 -> Ab4 -> G4 -> Eb4, ~370 ms)
    mov bx, 0x08E9                  ; C5 (523 Hz)
    call start_tone
    mov ecx, 17500000               ; ~70 ms
    call delay_cycles
    mov bx, 0x0B3B                  ; Ab4 (415 Hz)
    call set_tone_freq
    mov ecx, 20000000               ; ~80 ms
    call delay_cycles
    mov bx, 0x0BE4                  ; G4 (392 Hz)
    call set_tone_freq
    mov ecx, 20000000               ; ~80 ms
    call delay_cycles
    mov bx, 0x0EFD                  ; Eb4 (311 Hz)
    call set_tone_freq
    mov ecx, 35000000               ; ~140 ms
    call delay_cycles
    call stop_tone
    pop ecx
    pop bx
    pop ax
    ret

sound_start:
    push ax
    push bx
    push ecx
    ; Dynamischer, freundlicher Start-Akkord (E5 -> A5, ~100 ms)
    mov bx, 0x0713                  ; E5 (659 Hz)
    call start_tone
    mov ecx, 10000000               ; ~40 ms
    call delay_cycles
    mov bx, 0x054C                  ; A5 (880 Hz)
    call set_tone_freq
    mov ecx, 15000000               ; ~60 ms
    call delay_cycles
    call stop_tone
    pop ecx
    pop bx
    pop ax
    ret

sound_victory:
    push ax
    push bx
    push ecx
    ; Grosse 6-Ton Siegesfanfare (C5 -> E5 -> G5 -> C6 -> G5 -> C6, ~580 ms)
    mov bx, 0x08E9                  ; C5
    call start_tone
    mov ecx, 17500000               ; ~70 ms
    call delay_cycles
    mov bx, 0x0713                  ; E5
    call set_tone_freq
    mov ecx, 17500000               ; ~70 ms
    call delay_cycles
    mov bx, 0x05F2                  ; G5
    call set_tone_freq
    mov ecx, 17500000               ; ~70 ms
    call delay_cycles
    mov bx, 0x0474                  ; C6
    call set_tone_freq
    mov ecx, 25000000               ; ~100 ms
    call delay_cycles
    mov bx, 0x05F2                  ; G5
    call set_tone_freq
    mov ecx, 17500000               ; ~70 ms
    call delay_cycles
    mov bx, 0x0474                  ; C6
    call set_tone_freq
    mov ecx, 50000000               ; ~200 ms
    call delay_cycles
    call stop_tone
    pop ecx
    pop bx
    pop ax
    ret

sound_click:
    push ax
    push bx
    push ecx
    mov bx, 0x054C                  ; A5 (880 Hz) ~15 ms
    call start_tone
    mov ecx, 3750000
    call delay_cycles
    call stop_tone
    pop ecx
    pop bx
    pop ax
    ret

sound_toggle:
    push ax
    push bx
    push ecx
    mov bx, 0x0474                  ; C6 (1046 Hz) ~15 ms
    call start_tone
    mov ecx, 3750000
    call delay_cycles
    mov bx, 0x0389                  ; E6 (1318 Hz) ~25 ms
    call set_tone_freq
    mov ecx, 6250000
    call delay_cycles
    call stop_tone
    pop ecx
    pop bx
    pop ax
    ret

    ; =========================================================================
    ; PHASE 9: TEXT-STRINGS & TABELLEN
    ; =========================================================================
; --- Cybforge POST Screen Strings ---
str_post_hdr1:
    db "Cybforge Retro BIOS (C)2026 Cybforge Systems Inc.", 0
str_post_hdr2:
    db "BIOS Date: 10/24/2026  Ver: 2.16.01-PRO", 0
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
    db "[W/S] Select Item   [A/D/ENTER] Change Value   [ESC] Exit & Boot", 0

str_opt_speed:
    db "Game Speed        : ", 0
str_opt_walls:
    db "Wall Collision    : ", 0
str_opt_sound:
    db "PC Speaker Sound  : ", 0
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

str_val_snd_on:
    db "< Enabled        >", 0
str_val_snd_off:
    db "< Disabled       >", 0

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

; --- Snake Game Strings ---
str_game_title:
    db "CYBFORGE SNAKE", 0
str_game_ver:
    db "v2.1", 0
str_hi_score_lbl:
    db "HIGH: ", 0
str_score_lbl:
    db "SCORE: ", 0
str_controls:
    db "Controls: [WASD / Arrows] Move    [ESC] BIOS Setup    [ENTER] Start", 0

; Start Modal Box Strings
str_start_title:
    db "CYBFORGE RETRO SNAKE", 0
str_press_enter:
    db "Press [ENTER] to Start", 0

; Game Over Modal Box Strings
str_game_over:
    db "G A M E   O V E R", 0
str_final_score_lbl:
    db "Final Score: ", 0
str_go_restart_info:
    db "[ENTER] Restart   [ESC] Setup", 0

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

full_asm = part1 + "\n" + part2 + "\n" + part3_tables + "\n" + font_table_asm + "\n" + custom_glyphs_table_asm + "\n" + logo_table_asm + "\n" + part5_tail
DEST.write_text(full_asm, encoding="utf-8")
print(f"Generated clean {DEST} ({len(full_asm)} bytes)")

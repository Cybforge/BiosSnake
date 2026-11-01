; =============================================================================
; Bare-Metal x86 BIOS ROM (64 KB) für QEMU – BLUE BOX EDITION
; Startet bei 0xFFFFFFF0 (0xF000:0xFFF0), initialisiert CAR/MTRR, i440FX PAM/DRB,
; PCI-VGA, Real-Mode-IVT, PIC, A20, 16550 UART, VGA-Font & zeichnet die Box!
; =============================================================================

[BITS 16]
[ORG 0x0000]                ; Gemappt auf Physisch 0xF0000 - 0xFFFFF (CS = 0xF000)

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

; --- RAM-Adressen fuer DVD-Logo Animation (im freien RAM bei 0x0000) ---
CLEAN_BUF equ 0x1000        ; 4000 Bytes Puffer (0x1000..0x1FA0) fuer Original-Screen
POS_X1    equ 0x2000        ; Position & Richtung Ausrufezeichen 1
POS_Y1    equ 0x2002
DIR_X1    equ 0x2004
DIR_Y1    equ 0x2006
POS_X2    equ 0x2008        ; Position & Richtung Ausrufezeichen 2
POS_Y2    equ 0x200A
DIR_X2    equ 0x200C
DIR_Y2    equ 0x200E
SOUND_TIMER equ 0x2010     ; Timer fuer PC-Speaker Tonlaenge

bios_start:
    cli                     ; 1. Maskierbare Interrupts sofort sperren
    cld                     ; Direction-Flag löschen

    ; --- NMI (Non-Maskable Interrupt) über CMOS-Port 0x70 deaktivieren ---
    mov al, 0x80
    out 0x70, al
    in  al, 0x71

    ; =========================================================================
    ; SCHRITT 1: CPU Cache & Cache-as-RAM (CAR) sauber initialisieren
    ; =========================================================================
    mov eax, 1
    cpuid
    bt  edx, 12             ; MTRR Feature-Bit prüfen
    jnc .skip_mtrr

    mov eax, cr0
    or  eax, 0x40000000     ; CR0.CD = 1 (Cache Disable)
    and eax, 0xDFFFFFFF     ; CR0.NW = 0
    mov cr0, eax
    invd                    ; Internen Cache invalidieren

    mov ecx, 0x0250         ; IA32_MTRR_FIX64K_00000
    mov eax, 0x06060606     ; Write-Back (0x06)
    mov edx, 0x06060606
    wrmsr

    mov ecx, 0x02FF         ; IA32_MTRR_DEF_TYPE
    mov eax, 0x00000C06     ; Enable MTRRs + Fixed MTRRs + Default Write-Back
    xor edx, edx
    wrmsr

.skip_mtrr:
    mov eax, cr0
    and eax, 0x9FFFFFFF     ; L1/L2 Cache aktivieren (CD=0, NW=0)
    mov cr0, eax

    ; =========================================================================
    ; SCHRITT 2: Northbridge (i440FX 00:00.0) & PCI-VGA (00:02.0) aufwecken
    ; =========================================================================
    mov eax, 0x80000058     ; Bus 0, Dev 0, Func 0, Offset 0x58 (DRAMC & PAM0..2)
    mov dx, 0x0CF8
    out dx, eax
    mov dx, 0x0CFC
    in  eax, dx
    and eax, 0x000000FF     ; PAM0 (AH) = 0x00 (BIOS-ROM bleibt lesbar)
    or  eax, 0x33330000     ; PAM1 & PAM2 = R/W RAM
    out dx, eax

    mov eax, 0x8000005C     ; PAM3..PAM6 (Offset 0x5C..0x5F) auf R/W RAM
    mov dx, 0x0CF8
    out dx, eax
    mov dx, 0x0CFC
    mov eax, 0x33333333
    out dx, eax

    mov eax, 0x80000060     ; DRAM Row Boundary Register (DRB0..DRB3)
    mov dx, 0x0CF8
    out dx, eax
    mov dx, 0x0CFC
    in  eax, dx
    test eax, eax
    jnz .ram_ready
    mov eax, 0x08080808     ; Fallback: 64 MB DRAM
    out dx, eax
.ram_ready:

    ; PCI-VGA-Grafikkarte (Bus 0, Dev 2, Func 0, Offset 0x04 Command Reg)
    mov eax, 0x80001004
    mov dx, 0x0CF8
    out dx, eax
    mov dx, 0x0CFC
    in  eax, dx
    or  eax, 0x00000007     ; I/O + Memory + Bus Master aktivieren
    out dx, eax

    ; =========================================================================
    ; SCHRITT 3: Stack, Segmente & Real-Mode-IVT (Interrupt Vector Table)
    ; =========================================================================
    xor ax, ax
    mov ss, ax
    mov sp, 0x7C00
    mov es, ax

    mov ax, 0xF000
    mov ds, ax

    xor di, di
    mov cx, 256
.ivt_init_loop:
    mov ax, dummy_isr
    stosw
    mov ax, 0xF000
    stosw
    loop .ivt_init_loop

    ; =========================================================================
    ; SCHRITT 4: Fast-A20, 8259 PIC & 16550 UART (inkl. FIFO)
    ; =========================================================================
    in  al, 0x92
    or  al, 0x02
    and al, 0xFE
    out 0x92, al

    mov al, 0x11
    out 0x20, al
    out 0xA0, al
    mov al, 0x08
    out 0x21, al
    mov al, 0x70
    out 0xA1, al
    mov al, 0x04
    out 0x21, al
    mov al, 0x02
    out 0xA1, al
    mov al, 0x01
    out 0x21, al
    out 0xA1, al
    mov al, 0xFF            ; Alle IRQs maskieren
    out 0x21, al
    out 0xA1, al

    
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

    ; COM1 (0x3F8) auf 115200 Baud, 8N1
    xor al, al
    mov dx, 0x3F9
    out dx, al
    mov al, 0x80
    mov dx, 0x3FB
    out dx, al
    mov al, 0x01
    mov dx, 0x3F8
    out dx, al
    xor al, al
    mov dx, 0x3F9
    out dx, al
    mov al, 0x03
    mov dx, 0x3FB
    out dx, al
    mov al, 0xC7
    mov dx, 0x3FA
    out dx, al
    mov al, 0x03
    mov dx, 0x3FC
    out dx, al

    ; =========================================================================
    ; SCHRITT 5: Kompletter Bare-Metal VGA-Bringup (80x25 Text Mode)
    ; =========================================================================
    mov dx, 0x3C2
    mov al, 0x67
    out dx, al

    mov dx, 0x3C4
    mov ax, 0x0100          ; Sequencer Sync-Reset
    out dx, ax

    mov si, vga_seq_table
    mov cx, 4
    mov ah, 1
.seq_loop:
    mov dx, 0x3C4
    mov al, ah
    out dx, al
    inc dx
    lodsb
    out dx, al
    inc ah
    loop .seq_loop

    mov dx, 0x3C4
    mov ax, 0x0300          ; Sync-Reset beenden
    out dx, ax

    mov dx, 0x3D4
    mov ax, 0x0011          ; CRTC Schreibschutz aufheben
    out dx, ax

    mov si, vga_crtc_table
    mov cx, 25
    xor ah, ah
.crtc_loop:
    mov dx, 0x3D4
    mov al, ah
    out dx, al
    inc dx
    lodsb
    out dx, al
    inc ah
    loop .crtc_loop

    mov si, vga_gc_table
    mov cx, 9
    xor ah, ah
.gc_loop:
    mov dx, 0x3CE
    mov al, ah
    out dx, al
    inc dx
    lodsb
    out dx, al
    inc ah
    loop .gc_loop

    mov dx, 0x3DA
    in  al, dx              ; Flip-Flop zurücksetzen
    mov dx, 0x3C0
    xor ah, ah
.ac_pal_loop:
    mov al, ah
    out dx, al
    out dx, al              ; Identitäts-Mapping 0..15 -> DAC 0..15
    inc ah
    cmp ah, 16
    jb  .ac_pal_loop

    mov si, vga_ac_ext_table
    mov cx, 5
.ac_ext_loop:
    mov al, ah
    out dx, al
    lodsb
    out dx, al
    inc ah
    loop .ac_ext_loop

    mov dx, 0x3DA
    in  al, dx
    mov dx, 0x3C0
    mov al, 0x20            ; Video-Output freigeben (PAS=1)
    out dx, al

    ; PEL Mask Register (0x3C6) auf 0xFF
    mov dx, 0x3C6
    mov al, 0xFF
    out dx, al

    ; =========================================================================
    ; SCHRITT 5.8: VGA DAC Palette für Schwarz, Blau, Grün & Weiß laden
    ; =========================================================================
    mov dx, 0x3C8
    xor al, al
    out dx, al              ; Start bei DAC-Index 0
    mov dx, 0x3C9
    mov si, vga_dac_table
    mov cx, 16 * 3          ; 16 Farben * 3 Bytes (R, G, B)
.dac_load_loop:
    lodsb
    out dx, al
    loop .dac_load_loop

    ; =========================================================================
    ; SCHRITT 6: Bitmap-Font sauber in VGA Plane 2 (0xA0000) laden
    ; =========================================================================
    mov dx, 0x3C4
    mov ax, 0x0100
    out dx, ax
    mov ax, 0x0402          ; SR02 = Plane 2
    out dx, ax
    mov ax, 0x0604          ; SR04 = Sequential
    out dx, ax
    mov ax, 0x0300
    out dx, ax

    mov dx, 0x3CE
    mov ax, 0x0204          ; GR04 = Plane 2
    out dx, ax
    mov ax, 0x0005          ; GR05 = Write Mode 0
    out dx, ax
    mov ax, 0x0406          ; GR06 = 0xA0000
    out dx, ax

    mov ax, 0xA000
    mov es, ax

    xor di, di
    xor ax, ax
    mov cx, 16384
    rep stosw

    mov si, font_table
.font_char_loop:
    lodsb
    test al, al
    jz  .font_done
    xor ah, ah
    shl ax, 5               ; Offset = ASCII * 32
    mov di, ax
    mov cx, 8
.font_row_loop:
    lodsb
    stosb                   ; Scanline 2n
    stosb                   ; Scanline 2n+1 (8x16 Font)
    loop .font_row_loop
    jmp .font_char_loop

.font_done:

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

    ; Zurück in den Odd/Even Text-Mode bei 0xB8000 schalten
    mov dx, 0x3C4
    mov ax, 0x0100
    out dx, ax
    mov ax, 0x0302          ; SR02 = Plane 0 & 1
    out dx, ax
    mov ax, 0x0204          ; SR04 = Odd/Even
    out dx, ax
    mov ax, 0x0300
    out dx, ax

    mov dx, 0x3CE
    mov ax, 0x0004
    out dx, ax
    mov ax, 0x1005
    out dx, ax
    mov ax, 0x0E06          ; GR06 = 0xB8000 Textfenster
    out dx, ax

    ; =========================================================================
    

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

    ; Navigation: W/S oder Pfeiltasten
    cmp al, 0x11                    ; 'W'
    je .sel_up
    cmp al, 0x48                    ; Up Arrow
    je .sel_up

    cmp al, 0x1F                    ; 'S'
    je .sel_down
    cmp al, 0x50                    ; Down Arrow
    je .sel_down

    ; Wert aendern / Auswaehlen: A/D, Pfeile, ENTER, SPACE
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
    mov byte [SETUP_SEL], 9         ; Max Zeilen-Index = 9
    jmp .redraw_setup

.sel_down:
    call sound_click
    mov al, [SETUP_SEL]
    cmp al, 9
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
    dec byte [CFG_SOUND]
    and byte [CFG_SOUND], 3
    call sound_toggle
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
    jne .p6
    dec byte [CFG_WIN]
    jns .redraw_setup
    mov byte [CFG_WIN], 3
    jmp .redraw_setup
.p6:
    cmp al, 6
    jne .p7
    ; Color Theme: 0=Cyber, 1=Matrix, 2=Amber, 3=CGA
    dec byte [CFG_THEME]
    jns .th_prev_ok
    mov byte [CFG_THEME], 3
.th_prev_ok:
    call apply_color_theme
    jmp .redraw_setup
.p7:
    cmp al, 7
    jne .redraw_setup
    ; Game Arena: 0=Open, 1=Pillars, 2=Maze
    dec byte [CFG_ARENA]
    jns .redraw_setup
    mov byte [CFG_ARENA], 2
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
    inc byte [CFG_SOUND]
    and byte [CFG_SOUND], 3
    call sound_toggle
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
    jne .n6
    inc byte [CFG_WIN]
    cmp byte [CFG_WIN], 4
    jb .redraw_setup
    mov byte [CFG_WIN], 0
    jmp .redraw_setup
.n6:
    cmp al, 6
    jne .n7
    inc byte [CFG_THEME]
    cmp byte [CFG_THEME], 4
    jb .th_next_ok
    mov byte [CFG_THEME], 0
.th_next_ok:
    call apply_color_theme
    jmp .redraw_setup
.n7:
    cmp al, 7
    jne .redraw_setup
    inc byte [CFG_ARENA]
    cmp byte [CFG_ARENA], 3
    jb .redraw_setup
    mov byte [CFG_ARENA], 0
    jmp .redraw_setup

.val_enter:
    mov al, [SETUP_SEL]
    cmp al, 8
    je .do_reset_defaults
    cmp al, 9
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
    mov byte [CFG_THEME], 0
    mov byte [CFG_ARENA], 0
    call save_cmos_settings
    call apply_color_theme
    call sound_toggle
    jmp .redraw_setup

.exit_setup:
    call save_cmos_settings
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

    ; 3. Haupt-Optionskasten (Zeile 3 bis 17, Spalte 6 bis 73)
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

    ; 4. Hilfe-Kasten (Zeile 18 bis 23, Spalte 6 bis 73)
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

    ; 5. Fusszeile / Tastaturbedienung (Zeile 24)
    mov di, (24 * 80 + 8) * 2
    mov si, str_setup_footer
    mov ah, 0x1F
    call print_string

    ; 6. Menue-Punkte zeichnen (Zeilen 0..9)
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

    ; Zeile 1: Wall Collision (Row 5)
    mov bl, 1
    mov dh, 5
    mov si, str_opt_walls
    call draw_menu_row
    mov si, str_val_wall_solid
    cmp byte [CFG_WALLS], 1
    jne .draw_wall_val
    mov si, str_val_wall_wrap
.draw_wall_val:
    call draw_val_str

    ; Zeile 2: Sound Output (Row 6)
    mov bl, 2
    mov dh, 6
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

    ; Zeile 3: Snake Face Style (Row 7)
    mov bl, 3
    mov dh, 7
    mov si, str_opt_face
    call draw_menu_row
    mov si, str_val_face_smile
    cmp byte [CFG_FACE], 1
    jne .draw_face_val
    mov si, str_val_face_cool
.draw_face_val:
    call draw_val_str

    ; Zeile 4: Starting Length (Row 8)
    mov bl, 4
    mov dh, 8
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

    ; Zeile 5: Victory Target (Row 9)
    mov bl, 5
    mov dh, 9
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

    ; Zeile 6: Color Theme (Row 10)
    mov bl, 6
    mov dh, 10
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

    ; Zeile 7: Game Arena (Row 11)
    mov bl, 7
    mov dh, 11
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

    ; Zeile 8: Reset Defaults (Row 13)
    mov bl, 8
    mov dh, 13
    mov si, str_opt_reset
    call draw_menu_row

    ; Zeile 9: Save & Boot Game (Row 14)
    mov bl, 9
    mov dh, 14
    mov si, str_opt_boot
    call draw_menu_row

    ; Info: Session High Score anzeigen bei Row 16
    mov di, (16 * 80 + 10) * 2
    mov si, str_hi_score_lbl
    mov ah, 0x1E                    ; Yellow
    call print_string
    mov ax, [HIGH_SCORE]
    call render_3digits_yellow

    ; 7. Dynamischen Hilfetext in Zeile 20/21 schreiben
    mov di, (20 * 80 + 9) * 2
    mov al, [SETUP_SEL]
    mov si, str_help_0
    cmp al, 0
    je .do_print_help
    mov si, str_help_1
    cmp al, 1
    je .do_print_help
    mov si, str_help_2
    cmp al, 2
    je .do_print_help
    mov si, str_help_3
    cmp al, 3
    je .do_print_help
    mov si, str_help_4
    cmp al, 4
    je .do_print_help
    mov si, str_help_5
    cmp al, 5
    je .do_print_help
    mov si, str_help_6
    cmp al, 6
    je .do_print_help
    mov si, str_help_7
    cmp al, 7
    je .do_print_help
    mov si, str_help_8
    cmp al, 8
    je .do_print_help
    mov si, str_help_9
.do_print_help:
    mov ah, 0x1E                    ; Yellow
    call print_string
    ret

draw_menu_row:
    ; Input: bl = row index (0..9), dh = screen row (Y), si = string
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
    ; Pruefen ob Signatur 0xCB bei Index 0x40 steht
    mov al, 0x40
    call cmos_read_byte
    cmp al, 0xCB
    jne .cmos_invalid

    ; Checksumme berechnen
    xor bl, bl
    mov cl, 0x40
.chk_loop:
    mov al, cl
    call cmos_read_byte
    xor bl, al
    inc cl
    cmp cl, 0x59
    jb .chk_loop

    mov al, 0x59
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

    ; Top 3 Leaderboard laden (15 Bytes)
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
    mov ah, 0xCB
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

    ; Top 3 Leaderboard schreiben
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

    ; Checksumme berechnen & schreiben
    xor bl, bl
    mov cl, 0x40
.save_chk:
    mov al, cl
    call cmos_read_byte
    xor bl, al
    inc cl
    cmp cl, 0x59
    jb .save_chk

    mov al, 0x59
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
    db "[W/S] Select Item   [A/D/ENTER] Change Value   [ESC] Exit & Boot", 0

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
    db "/ /:.     :\ ", 0
str_vic_t6:
    db '(  ":.     .:"  )', 0
str_vic_t7:
    db "'====)   (===='", 0
str_vic_t8:
    db ")   (", 0
str_vic_t9:
    db "_.'     '._", 0
str_vic_t10:
    db "/=============", 0
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

vga_seq_table:
    db 0x01, 0x03, 0x00, 0x02

; CRTC Registers (CR00 - CR18)
vga_crtc_table:
    db 0x5F, 0x4F, 0x50, 0x82, 0x55, 0x81, 0xBF, 0x1F
    db 0x00, 0x4F, 0x0D, 0x0E, 0x00, 0x00, 0x00, 0x00
    db 0x9C, 0x8E, 0x8F, 0x28, 0x1F, 0x96, 0xB9, 0xA3
    db 0xFF

; Graphics Controller Registers (GR00 - GR08)
vga_gc_table:
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x0E, 0x00, 0xFF

; Attribute Controller Registers AR10 - AR14
vga_ac_ext_table:
    db 0x04, 0x00, 0x0F, 0x00, 0x00

; 16-Farben VGA DAC Palette (Je 3 Bytes: R, G, B im Bereich 0..63)
vga_dac_table:
    db  0,  0,  0           ; 0x00: Schwarz (Screen-Hintergrund)
    db  0, 12, 48           ; 0x01: Kräftiges BIOS-Blau (Box-Hintergrund)
    db  0, 42,  0           ; 0x02: Dunkelgrün
    db  0, 42, 42           ; 0x03: Cyan
    db 42,  0,  0           ; 0x04: Rot
    db 42,  0, 42           ; 0x05: Magenta
    db 42, 21,  0           ; 0x06: Braun
    db 42, 42, 42           ; 0x07: Hellgrau
    db 21, 21, 21           ; 0x08: Dunkelgrau
    db 21, 21, 63           ; 0x09: Hellblau
    db 10, 63, 20           ; 0x0A: Matrix-Hellgrün ("Hello World from BIOS!")
    db 21, 63, 63           ; 0x0B: Hellcyan
    db 63, 21, 21           ; 0x0C: Hellrot
    db 63, 21, 63           ; 0x0D: Pink
    db 63, 63, 21           ; 0x0E: Gelb
    db 63, 63, 63           ; 0x0F: Reines Weiß ("die box geht!" + Rahmen)

; Kompakte 8x8 Bitmap-Font-Tabelle (wird beim Upload auf 8x16 verdoppelt)

align 8
sample_table:
    dd 0xFFFD0000 ; SND_CRUNCH
    dw 2206
    dd 0xFFFD113C ; SND_GOLDEN
    dw 6064
    dd 0xFFFD409C ; SND_CRASH
    dw 4962
    dd 0xFFFD6760 ; SND_START
    dw 3858
    dd 0xFFFD8584 ; SND_PAUSE
    dw 1764
    dd 0xFFFD934C ; SND_BOOT
    dw 5512
    dd 0xFFFDBE5C ; SND_GAMEOVER
    dw 9372
    dd 0xFFFE0794 ; SND_VICTORY
    dw 13230

font_table:
    db 0x01, 0x00, 0x00, 0x00, 0x1F, 0x18, 0x18, 0x18, 0x18
    db 0x02, 0x00, 0x00, 0x00, 0xF8, 0x18, 0x18, 0x18, 0x18
    db 0x03, 0x18, 0x18, 0x18, 0x1F, 0x00, 0x00, 0x00, 0x00
    db 0x04, 0x18, 0x18, 0x18, 0xF8, 0x00, 0x00, 0x00, 0x00
    db 0x05, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00
    db 0x06, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18
    db 0x07, 0x00, 0x3C, 0x7E, 0xDB, 0xFF, 0xC3, 0xE7, 0x7E
    db 0x08, 0x08, 0x1C, 0x08, 0x76, 0xFF, 0xFF, 0xFF, 0x7E
    db 0x09, 0x00, 0x3C, 0x7E, 0xFF, 0xDB, 0xFF, 0x7E, 0x3C
    db 0x0A, 0x00, 0x3C, 0x7E, 0xFF, 0xDB, 0x7E, 0x3C, 0x18
    db 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; ' '
    db 0x21, 0x18, 0x3C, 0x3C, 0x18, 0x18, 0x00, 0x18, 0x00 ; '!'
    db 0x22, 0x66, 0x66, 0x24, 0x00, 0x00, 0x00, 0x00, 0x00 ; '"'
    db 0x23, 0x6C, 0x6C, 0xFE, 0x6C, 0xFE, 0x6C, 0x6C, 0x00 ; '#'
    db 0x24, 0x18, 0x3E, 0x60, 0x3C, 0x06, 0x7C, 0x18, 0x00 ; '$'
    db 0x25, 0x00, 0x66, 0xA6, 0xD8, 0x1B, 0x65, 0x66, 0x00 ; '%'
    db 0x26, 0x30, 0x48, 0x30, 0x6E, 0xD9, 0xCE, 0x7B, 0x00 ; '&'
    db 0x27, 0x18, 0x18, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00 ; '''
    db 0x28, 0x0C, 0x18, 0x30, 0x30, 0x30, 0x18, 0x0C, 0x00 ; '('
    db 0x29, 0x30, 0x18, 0x0C, 0x0C, 0x0C, 0x18, 0x30, 0x00 ; ')'
    db 0x2A, 0x00, 0x66, 0x3C, 0xFF, 0x3C, 0x66, 0x00, 0x00 ; '*'
    db 0x2B, 0x00, 0x18, 0x18, 0x7E, 0x18, 0x18, 0x00, 0x00 ; '+'
    db 0x2C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x08 ; ','
    db 0x2D, 0x00, 0x00, 0x00, 0x7E, 0x00, 0x00, 0x00, 0x00 ; '-'
    db 0x2E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x00 ; '.'
    db 0x2F, 0x06, 0x0C, 0x18, 0x30, 0x60, 0xC0, 0x80, 0x00 ; '/'
    db 0x30, 0x3C, 0x66, 0x6E, 0x76, 0x66, 0x66, 0x3C, 0x00 ; '0'
    db 0x31, 0x18, 0x38, 0x18, 0x18, 0x18, 0x18, 0x7E, 0x00 ; '1'
    db 0x32, 0x3C, 0x66, 0x06, 0x0C, 0x18, 0x30, 0x7E, 0x00 ; '2'
    db 0x33, 0x7E, 0x06, 0x0C, 0x1C, 0x06, 0x66, 0x3C, 0x00 ; '3'
    db 0x34, 0x0C, 0x1C, 0x3C, 0x6C, 0xFE, 0x0C, 0x0C, 0x00 ; '4'
    db 0x35, 0x7E, 0x60, 0x7C, 0x06, 0x06, 0x66, 0x3C, 0x00 ; '5'
    db 0x36, 0x3C, 0x66, 0x60, 0x7C, 0x66, 0x66, 0x3C, 0x00 ; '6'
    db 0x37, 0x7E, 0x06, 0x0C, 0x18, 0x30, 0x30, 0x30, 0x00 ; '7'
    db 0x38, 0x3C, 0x66, 0x66, 0x3C, 0x66, 0x66, 0x3C, 0x00 ; '8'
    db 0x39, 0x3C, 0x66, 0x66, 0x3E, 0x06, 0x66, 0x3C, 0x00 ; '9'
    db 0x3A, 0x00, 0x18, 0x18, 0x00, 0x00, 0x18, 0x18, 0x00 ; ':'
    db 0x3B, 0x00, 0x18, 0x18, 0x00, 0x00, 0x18, 0x18, 0x08 ; ';'
    db 0x3C, 0x0C, 0x18, 0x30, 0x60, 0x30, 0x18, 0x0C, 0x00 ; '<'
    db 0x3D, 0x00, 0x00, 0x7E, 0x00, 0x7E, 0x00, 0x00, 0x00 ; '='
    db 0x3E, 0x30, 0x18, 0x0C, 0x06, 0x0C, 0x18, 0x30, 0x00 ; '>'
    db 0x3F, 0x3C, 0x66, 0x06, 0x0C, 0x18, 0x00, 0x18, 0x00 ; '?'
    db 0x40, 0x3C, 0x42, 0x99, 0xA5, 0xA5, 0x9E, 0x40, 0x3C ; '@'
    db 0x41, 0x3C, 0x66, 0x66, 0x7E, 0x66, 0x66, 0x66, 0x00 ; 'A'
    db 0x42, 0xFC, 0x66, 0x66, 0x7C, 0x66, 0x66, 0xFC, 0x00 ; 'B'
    db 0x43, 0x3C, 0x66, 0x60, 0x60, 0x60, 0x66, 0x3C, 0x00 ; 'C'
    db 0x44, 0xF8, 0x6C, 0x66, 0x66, 0x66, 0x6C, 0xF8, 0x00 ; 'D'
    db 0x45, 0xFE, 0x62, 0x68, 0x78, 0x68, 0x62, 0xFE, 0x00 ; 'E'
    db 0x46, 0xFE, 0x62, 0x68, 0x78, 0x68, 0x60, 0xF0, 0x00 ; 'F'
    db 0x47, 0x3C, 0x66, 0x60, 0x6E, 0x66, 0x66, 0x3C, 0x00 ; 'G'
    db 0x48, 0xC6, 0xC6, 0xC6, 0xFE, 0xC6, 0xC6, 0xC6, 0x00 ; 'H'
    db 0x49, 0x3C, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00 ; 'I'
    db 0x4A, 0x1E, 0x06, 0x06, 0x06, 0x06, 0x66, 0x3C, 0x00 ; 'J'
    db 0x4B, 0xC6, 0xCC, 0xD8, 0xF0, 0xD8, 0xCC, 0xC6, 0x00 ; 'K'
    db 0x4C, 0xF0, 0x60, 0x60, 0x60, 0x60, 0x62, 0xFE, 0x00 ; 'L'
    db 0x4D, 0xC6, 0xEE, 0xFE, 0xD6, 0xC6, 0xC6, 0xC6, 0x00 ; 'M'
    db 0x4E, 0xC6, 0xE6, 0xF6, 0xDE, 0xCE, 0xC6, 0xC6, 0x00 ; 'N'
    db 0x4F, 0x3C, 0x66, 0x66, 0x66, 0x66, 0x66, 0x3C, 0x00 ; 'O'
    db 0x50, 0xFC, 0x66, 0x66, 0x7C, 0x60, 0x60, 0xF0, 0x00 ; 'P'
    db 0x51, 0x3C, 0x66, 0x66, 0x66, 0x6E, 0x3C, 0x0E, 0x00 ; 'Q'
    db 0x52, 0xFC, 0x66, 0x66, 0x7C, 0x6C, 0x66, 0xE6, 0x00 ; 'R'
    db 0x53, 0x3C, 0x66, 0x60, 0x3C, 0x06, 0x66, 0x3C, 0x00 ; 'S'
    db 0x54, 0x7E, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x00 ; 'T'
    db 0x55, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00 ; 'U'
    db 0x56, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x6C, 0x38, 0x00 ; 'V'
    db 0x57, 0xC6, 0xC6, 0xC6, 0xD6, 0xFE, 0xEE, 0xC6, 0x00 ; 'W'
    db 0x58, 0xC6, 0xC6, 0x6C, 0x38, 0x6C, 0xC6, 0xC6, 0x00 ; 'X'
    db 0x59, 0x66, 0x66, 0x66, 0x3C, 0x18, 0x18, 0x18, 0x00 ; 'Y'
    db 0x5A, 0xFE, 0x06, 0x0C, 0x18, 0x30, 0x60, 0xFE, 0x00 ; 'Z'
    db 0x5B, 0x3C, 0x30, 0x30, 0x30, 0x30, 0x30, 0x3C, 0x00 ; '['
    db 0x5C, 0xC0, 0x60, 0x30, 0x18, 0x0C, 0x06, 0x02, 0x00 ; '\'
    db 0x5D, 0x3C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x3C, 0x00 ; ']'
    db 0x5E, 0x18, 0x3C, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00 ; '^'
    db 0x5F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF ; '_'
    db 0x60, 0x30, 0x18, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x00 ; '`'
    db 0x61, 0x00, 0x00, 0x3C, 0x06, 0x3E, 0x66, 0x3E, 0x00 ; 'a'
    db 0x62, 0xE0, 0x60, 0x7C, 0x66, 0x66, 0x66, 0x7C, 0x00 ; 'b'
    db 0x63, 0x00, 0x00, 0x3C, 0x66, 0x60, 0x66, 0x3C, 0x00 ; 'c'
    db 0x64, 0x1C, 0x0C, 0x3C, 0x6C, 0x6C, 0x6C, 0x3E, 0x00 ; 'd'
    db 0x65, 0x00, 0x00, 0x3C, 0x66, 0x7E, 0x60, 0x3C, 0x00 ; 'e'
    db 0x66, 0x1C, 0x36, 0x30, 0x78, 0x30, 0x30, 0x78, 0x00 ; 'f'
    db 0x67, 0x00, 0x00, 0x3E, 0x66, 0x66, 0x3E, 0x06, 0x3C ; 'g'
    db 0x68, 0xE0, 0x60, 0x6C, 0x76, 0x66, 0x66, 0xE6, 0x00 ; 'h'
    db 0x69, 0x18, 0x00, 0x38, 0x18, 0x18, 0x18, 0x3C, 0x00 ; 'i'
    db 0x6A, 0x0C, 0x00, 0x1C, 0x0C, 0x0C, 0x0C, 0x6C, 0x38 ; 'j'
    db 0x6B, 0xE0, 0x60, 0x66, 0x6C, 0x78, 0x6C, 0xE6, 0x00 ; 'k'
    db 0x6C, 0x38, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00 ; 'l'
    db 0x6D, 0x00, 0x00, 0xEC, 0xFE, 0xD6, 0xD6, 0xD6, 0x00 ; 'm'
    db 0x6E, 0x00, 0x00, 0xDC, 0x66, 0x66, 0x66, 0x66, 0x00 ; 'n'
    db 0x6F, 0x00, 0x00, 0x3C, 0x66, 0x66, 0x66, 0x3C, 0x00 ; 'o'
    db 0x70, 0x00, 0x00, 0xDC, 0x66, 0x66, 0x7C, 0x60, 0xF0 ; 'p'
    db 0x71, 0x00, 0x00, 0x3B, 0x66, 0x66, 0x3E, 0x06, 0x0F ; 'q'
    db 0x72, 0x00, 0x00, 0xDC, 0x76, 0x66, 0x60, 0xF0, 0x00 ; 'r'
    db 0x73, 0x00, 0x00, 0x3E, 0x60, 0x3C, 0x06, 0x7C, 0x00 ; 's'
    db 0x74, 0x30, 0x30, 0x7C, 0x30, 0x30, 0x34, 0x18, 0x00 ; 't'
    db 0x75, 0x00, 0x00, 0xC6, 0xC6, 0xC6, 0xC6, 0x7E, 0x00 ; 'u'
    db 0x76, 0x00, 0x00, 0xC6, 0xC6, 0xC6, 0x6C, 0x38, 0x00 ; 'v'
    db 0x77, 0x00, 0x00, 0xC6, 0xD6, 0xD6, 0xFE, 0x6C, 0x00 ; 'w'
    db 0x78, 0x00, 0x00, 0xC6, 0x6C, 0x38, 0x6C, 0xC6, 0x00 ; 'x'
    db 0x79, 0x00, 0x00, 0xC6, 0xC6, 0x66, 0x3E, 0x06, 0x3C ; 'y'
    db 0x7A, 0x00, 0x00, 0x7E, 0x0C, 0x18, 0x30, 0x7E, 0x00 ; 'z'
    db 0x7B, 0x0E, 0x18, 0x18, 0x70, 0x18, 0x18, 0x0E, 0x00 ; '{'
    db 0x7C, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x00 ; '|'
    db 0x7D, 0x70, 0x18, 0x18, 0x0E, 0x18, 0x18, 0x70, 0x00 ; '}'
    db 0x7E, 0x76, 0xDC, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; '~'
    db 0

custom_glyphs_table:
    db 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3F, 0x20, 0x3F, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24
    db 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFC, 0x04, 0xFC, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24
    db 0x03, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x3F, 0x20, 0x3F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x04, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0xFC, 0x04, 0xFC, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x06, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24
    db 0x07, 0x00, 0x3C, 0x7E, 0xFF, 0xC3, 0xDB, 0xDB, 0xFF, 0xFF, 0xBD, 0x99, 0xC3, 0x7E, 0x7E, 0x3C, 0x00
    db 0x08, 0x06, 0x0E, 0x0C, 0x18, 0x10, 0x76, 0xFF, 0xDF, 0xBF, 0xFF, 0xFF, 0xFF, 0x7E, 0x7E, 0x3C, 0x00
    db 0x09, 0x3C, 0x7E, 0xFF, 0xEF, 0xD7, 0xBB, 0x7D, 0xFF, 0xEF, 0xD7, 0xBB, 0x7D, 0xFF, 0x7E, 0x7E, 0x3C
    db 0x0A, 0x00, 0x3C, 0x7E, 0xFF, 0x7E, 0xDB, 0xD7, 0xCF, 0xFF, 0xFF, 0xE7, 0xDB, 0x7E, 0x7E, 0x3C, 0x00
    db 0

logo_font_table:
    db 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x81, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x82, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x03
    db 0x83, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7F, 0xFF, 0xFF, 0xFF
    db 0x84, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF
    db 0x85, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF
    db 0x86, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF
    db 0x87, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0xC0, 0xE0
    db 0x88, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x89, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x8A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x03
    db 0x8B, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x03, 0x07, 0x0F, 0x1F, 0x3F, 0x7F, 0xFF, 0xFF, 0xFF
    db 0x8C, 0x07, 0x0F, 0x1F, 0x3F, 0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE, 0xFC, 0xF8
    db 0x8D, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFC, 0xF8, 0xF0, 0xE0, 0x80, 0x00, 0x00, 0x00, 0x00
    db 0x8E, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3F, 0x7F, 0xFF
    db 0x8F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF
    db 0x90, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF
    db 0x91, 0xE0, 0xF0, 0xF8, 0xFC, 0xFE, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF
    db 0x92, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF
    db 0x93, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF0, 0xF0, 0xE0
    db 0x94, 0x07, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F
    db 0x95, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
    db 0x96, 0xF0, 0xE0, 0xC0, 0x80, 0x80, 0x00, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80
    db 0x97, 0x01, 0x03, 0x07, 0x0F, 0x1F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x1F, 0x0F, 0x07, 0x03
    db 0x98, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE
    db 0x99, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1F, 0x3F
    db 0x9A, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF
    db 0x9B, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF
    db 0x9C, 0xFF, 0xFF, 0xFF, 0xFE, 0xFC, 0xF8, 0xF0, 0xE0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFE, 0xFF
    db 0x9D, 0xC0, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x9E, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F, 0x0F
    db 0x9F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
    db 0xA0, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0xC0, 0xE0, 0xF0, 0xF8
    db 0xA1, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0xA2, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE
    db 0xA3, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F
    db 0xA4, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0
    db 0xA5, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0xA6, 0xFE, 0xFC, 0xF8, 0xF0, 0xE0, 0xC0, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0xA7, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0xA8, 0x07, 0x03, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0xA9, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F, 0x3F, 0x1F, 0x0F, 0x07, 0x03, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0xAA, 0xFC, 0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F, 0x3F, 0x1F, 0x0F
    db 0xAB, 0x00, 0x00, 0x00, 0x80, 0xC0, 0xE0, 0xF0, 0xF8, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
    db 0xAC, 0xFE, 0xFE, 0xFE, 0xFE, 0xFE, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
    db 0xAD, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x1F, 0x1F, 0xCF, 0xE7, 0xF3, 0xF9, 0xFC, 0xFC, 0xFE, 0xFF
    db 0xAE, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0x70, 0x30, 0x30
    db 0xAF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0xB0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0xB1, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0xB2, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0xB3, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0xB4, 0x07, 0x03, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0xB5, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0xB6, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0xB7, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0xB8, 0x80, 0xC0, 0xE0, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0xB9, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0xBA, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0xBB, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0

times 0xFFF0 - ($ - $$) db 0xFF

reset_vector:               ; Physisch 0xFFFFFFF0 / Alias 0xF000:0xFFF0
    jmp 0xF000:bios_start   ; 5 Bytes (0xFFF0..0xFFF4)
    db "10/23/26"           ; 8 Bytes (0xFFF5..0xFFFC)
    db 0x00                 ; 1 Byte  (0xFFFD)
    db 0xFC                 ; 1 Byte  (0xFFFE): System Model ID (PC/AT)
    db 0x00                 ; 1 Byte  (0xFFFF) -> Exakt 65536 Bytes
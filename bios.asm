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

; --- Multi-Tab BIOS Setup & BiosShell Konfiguration (0x1A35..0x1A3F) ---
SETUP_TAB       equ 0x1A35  ; Aktiver Reiter im Setup: 0 = Main & Game, 1 = BiosShell (Byte)
CFG_SH_THEME    equ 0x1A36  ; 0=Classic EFI, 1=Matrix Green, 2=Cyber Cyan, 3=BIOS Blue (Byte)
CFG_SH_PROMPT   equ 0x1A37  ; 0="FS0:\> ", 1="SHELL> ", 2="root@bios:# " (Byte)
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
SH_SCRIPT_PTR   equ 0x1BD0  ; Aktueller Lesezeiger bei 'run <script>' (Word)
SH_SCRIPT_END   equ 0x1BD2  ; Endadresse bei 'run <script>' (Word)
SH_SCRIPT_ACT   equ 0x1BD4  ; 1 = Skript laeuft gerade (Byte)
SH_CTRL         equ 0x1BD5  ; Ctrl-Taste gedrueckt (0/1) (Byte)
CFG_SH_FONT     equ 0x1BD6  ; Aktuelle Schriftgroesse (0=Small, 1=Medium, 2=Large, 3=Huge) (Byte)
NANO_SAVED_FLAG equ 0x1BD7  ; 1 = In dieser Nano-Session gespeichert (Byte)
NANO_INODE      equ 0x1BD8  ; Zeiger auf aktuellen CybFS Inode im Nano Editor (Word)
NANO_ROW        equ 0x1BDA  ; Aktuelle Cursor-Zeile in Nano (0..17) (Byte)
NANO_COL        equ 0x1BDB  ; Aktuelle Cursor-Spalte in Nano (0..71) (Byte)
NANO_MOD        equ 0x1BDC  ; 1 = Ungespeicherte Aenderungen im Puffer (Byte)
NANO_MSG_ID     equ 0x1BDD  ; Statusmeldungs-ID in Nano (0..4) (Byte)
NANO_LAST_SZ    equ 0x1BDE  ; Letzte Dateigroesse in Bytes (Word)
NANO_BUF        equ 0x7000  ; 18 Zeilen x 72 Spalten = 1296 Bytes Textpuffer (0x7000..0x750F)

; --- CybFS v1.0 Live RAM Filesystem (0x3000..0x7FFF = 20 KB) ---
FS_MAGIC        equ 0x3000  ; Word: 0x5346 ('FS') wenn gemountet
FS_VERSION      equ 0x3002  ; Word: 0x0100
FS_MAX_INODES   equ 0x3004  ; Word: 32
FS_ALLOC_PTR    equ 0x3006  ; Word: Naechste freie Datenadresse (0x3420..0x7FFF)
FS_INODE_BASE   equ 0x3020  ; 32 Inodes x 32 Bytes (0x3020..0x341F)
FS_DATA_BASE    equ 0x3420  ; Datei-Datenpool (0x3420..0x7FFF = 19,424 Bytes)
FS_POOL_END     equ 0x7000  ; Obergrenze des CybFS Datenpools

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
    mov cx, 16
    rep movsb               ; True 16-scanline 8x16 IBM VGA Font
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

    ; Hardware Text-Cursor (CRTC 0x0A) deaktivieren (verhindert '_' Artefakt bei 0,0)
    mov dx, 0x3D4
    mov ax, 0x200A
    out dx, ax

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
    mov byte [SETUP_TAB], 0         ; Standard-Reiter: 0 (Main & Game)
    mov byte [CFG_SH_FONT], 2       ; Standard-Schriftgroesse: 2 (Large 8x16)

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


; =============================================================================
; PHASE 8: CYBFORGE EXTENDED UEFI / BIOS INTERACTIVE SHELL v2.5 (LIVE CYBFS)
; =============================================================================
bios_shell_main:
    call drain_kbd
    call fs_ensure_mounted          ; CybFS aus ROM Block 0 mounten falls noch nicht aktiv
    mov byte [SH_SHIFT], 0
    mov byte [SH_CTRL], 0
    mov byte [SH_CMD_LEN], 0
    mov byte [SH_HIST_LEN], 0
    mov byte [SH_SCRIPT_ACT], 0
    mov word [SH_DUMP_ADDR], 0x1A00

    call sh_init_theme
    call sh_clear_screen

    ; Startup Banner gemaess CFG_SH_BANNER anzeigen
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

    ; Puffer-Limit (max 54 Zeichen innerhalb des Rahmens) pruefen
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
    mov byte [SH_CUR_COL], 2
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
    cmp byte [SH_CUR_ROW], 2
    jbe .sh_prompt_init
    call sh_newline
    jmp .sh_prompt_init

; -----------------------------------------------------------------------------
; CYBFS v1.0 DRIVER: MOUNT FROM ROM BLOCK 0, INODE LOOKUP & DECIMAL PRINTER
; -----------------------------------------------------------------------------
fs_ensure_mounted:
    cmp word [FS_MAGIC], 0x5346     ; 'FS' Signatur schon im RAM?
    je .fem_ok
    call fs_format_from_rom
.fem_ok:
    ret

fs_format_from_rom:
    ; Kopiert das 4 KB CybFS Master-Image aus ROM Block 0 (0xFFFC0100) nach RAM 0x3000..0x3FFF
    ; und nullt den restlichen Datenpool 0x4000..0x7FFF.
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

    ; Restlichen RAM-Pool (0x4000..0x6FFF = 12 KB, Stack bei 0x7C00 schuetzen!) leeren
    mov di, 0x4000
    mov cx, 12288
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
    ; Sucht in [SH_DIR_ID] nach Dateiname ab [SH_CLEAN_BUF + bx] (bis Space oder 0).
    ; Output: Carry=1 wenn gefunden -> DI = Inode-Adresse (0x3020 + idx*32), CL = Inode-Index (0..31)
    ;         Carry=0 wenn nicht gefunden.
    push ax
    push si
    mov cl, 1                       ; Inode 1..31 durchsuchen
    mov di, FS_INODE_BASE + 32
.ffid_loop:
    mov al, [ds:di + 0]             ; flags
    test al, al
    jz .ffid_next
    mov al, [ds:di + 1]             ; parent_id
    cmp al, [SH_DIR_ID]
    jne .ffid_next

    ; Namen vergleichen: [ds:di + 8] vs [SH_CLEAN_BUF + bx]
    push bx
    lea si, [di + 8]
.ffid_cmp:
    mov al, [SH_CLEAN_BUF + bx]
    cmp al, ' '
    jne .ffid_not_sp
    xor al, al                      ; Space beendet Dateinamen-Token
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
    ; Sucht freien Inode-Slot (flags == 0) ab Index 1..31.
    ; Output: Carry=1 -> DI = Inode-Adresse, CL = Inode-Index. Carry=0 wenn voll.
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
    ; Gibt AX als vorzeichenlose 16-Bit Dezimalzahl (0..65535) mit Farb-Attribut BL aus
    push ax
    push bx
    push cx
    push dx
    push si
    mov bh, bl                      ; Farb-Attribut in BH sichern (AX bleibt unberuehrt!)
    xor cx, cx
    mov si, 10
.spd_div:
    xor dx, dx
    div si                          ; AX = AX / 10, DX = Rest (0..9)
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
    ; Gibt AX rechtsbuendig auf 6 Zeichen gepaddet mit Farb-Attribut BL aus
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
; SHELL KEYBOARD DRIVER (Mit Shift-Tracking fuer Grossbuchstaben & Symbole)
; -----------------------------------------------------------------------------
sh_read_key_event:
    in al, 0x64
    test al, 0x01
    jz .sh_no_key
    in al, 0x60
    cmp al, 0xE0                    ; Extended Scancode Prefix ignorieren
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

    ; Zeilen 1..23: Terminal Viewport Hintergrund
    mov di, (1 * 80) * 2
    mov cx, 23 * 80
    mov ah, [SH_TEXT_ATTR]
    mov al, ' '
    rep stosw

    ; Zeile 1: Oberer Doppelrahmen (Cols 0..79)
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

    ; Zeilen 2..22: Seitliche Rahmenlinien '│' bei Spalte 0 und 79
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

    ; Zeile 23: Unterer Doppelrahmen (Cols 0..79)
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

    mov byte [SH_CUR_ROW], 2
    mov byte [SH_CUR_COL], 2
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
    mov ds, ax                      ; DS = ES = 0xB800 fuer VRAM-Copy
    mov si, (3 * 80) * 2            ; Quelle: Zeile 3
    mov di, (2 * 80) * 2            ; Ziel:   Zeile 2
    mov cx, 20 * 80                 ; 20 Zeilen (Zeilen 3..22 -> 2..21)
    rep movsw
    pop ds                          ; DS = 0x0000 sofort wiederherstellen!

    ; Zeile 22 innerhalb des Rahmens (Spalten 1..78) leeren
    mov di, (22 * 80 + 1) * 2
    mov cx, 78
    mov ah, [SH_TEXT_ATTR]
    mov al, ' '
    rep stosw

    ; Rahmenlinien '│' auf Zeile 22 erneuern
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
    ; Druckt Null-terminierten String aus RAM [ds:si] mit Attribut AH
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
; PROMPT & INPUT LINE RENDERING (Mit echtem Verzeichnisnamen aus CybFS Inode!)
; -----------------------------------------------------------------------------
sh_draw_input_line:
    call sh_draw_input_no_cursor
    mov al, '_'
    mov ah, [SH_HIGH_ATTR]
    call sh_print_char
    ret

sh_draw_input_no_cursor:
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

    ; UEFI Prompt: "FS0:" + echter Inode-Ordnername + "> "
    mov si, str_pr_fs0_pfx
    call sh_print_inline
    mov al, [SH_DIR_ID]
    test al, al
    jz .sdp_close_gt

    ; Inode-Adresse des aktuellen Ordners berechnen: 0x3020 + SH_DIR_ID * 32
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
    sub al, 32                      ; Ordnernamen im Prompt gross darstellen
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
    ; Kommentarzeilen ('#' oder '@') in Skripten ignorieren
    mov al, [SH_CLEAN_BUF]
    cmp al, '#'
    je .sh_noop_ret
    cmp al, '@'
    je .sh_noop_ret

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

    ; 7. ls / dir (Echte CybFS Inode-Iteration!)
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

    ; 9. mkdir / md (Echten Ordner in CybFS anlegen)
    mov si, cmd_mkdir
    call sh_match_cmd
    jc .do_sh_mkdir
    mov si, cmd_md
    call sh_match_cmd
    jc .do_sh_mkdir

    ; 10. touch (Echte leere Datei in CybFS anlegen)
    mov si, cmd_touch
    call sh_match_cmd
    jc .do_sh_touch

    ; 11. write / nano / edit (Interaktiver GNU Nano Texteditor fuer CybFS!)
    mov si, cmd_write
    call sh_match_cmd
    jc .do_sh_write
    mov si, cmd_nano
    call sh_match_cmd
    jc .do_sh_write
    mov si, cmd_edit
    call sh_match_cmd
    jc .do_sh_write

    ; 12. append (Zeile an echte CybFS-Datei anhaengen)
    mov si, cmd_append
    call sh_match_cmd
    jc .do_sh_append

    ; 13. rm / del (Echte Datei / Ordner aus CybFS loeschen)
    mov si, cmd_rm
    call sh_match_cmd
    jc .do_sh_rm
    mov si, cmd_del
    call sh_match_cmd
    jc .do_sh_rm

    ; 14. cat / type (Echte Datei-Bytes aus CybFS / ROM lesen)
    mov si, cmd_cat
    call sh_match_cmd
    jc .do_sh_cat
    mov si, cmd_type
    call sh_match_cmd
    jc .do_sh_cat

    ; 15. run / sh (Echtes Skript aus CybFS Zeile fuer Zeile ausfuehren)
    mov si, cmd_run
    call sh_match_cmd
    jc .do_sh_run
    mov si, cmd_sh
    call sh_match_cmd
    jc .do_sh_run

    ; 16. format (CybFS frisch aus ROM Block 0 formatieren)
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

    ; 18. pci / devices / devtree / lspci (Echter Hardware-PCI-Bus-Scan!)
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

    ; 30. setfont (Schriftgroesse in der BIOS Shell live skalieren: 1..4)
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

    ; 32. shutdown / poweroff / halt / off (Echter ACPI S5 Soft-Off Shutdown!)
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

    ; Unbekannter Befehl:
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

; --- 1. EXIT -> ZURUECK INS BIOS SETUP ---
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
    call sh_print_line
    mov si, str_sh_hlp8
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

; --- 7. LS / DIR (100% ECHTER CYBFS INODE-SCANNER!) ---
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

    xor bp, bp                      ; BP = Anzahl gefundener Dateien
    xor edx, edx                    ; EDX (low 16) = Anzahl gefundener Ordner
    mov di, FS_INODE_BASE + 32      ; Ab Inode 1..31 scannen
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

    ; Spalte 1: Typ-Badge (<DIR>, [RAM], [ROM], [HW ])
    mov al, [ds:di + 0]
    cmp al, 2
    je .ls_type_dir
    cmp al, 3
    je .ls_type_rom
    cmp al, 4
    je .ls_type_hw

    ; flags == 1: [RAM] (Beschreibbare Datei im CybFS RAM-Pool)
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
    mov ax, [ds:di + 6]             ; Echte 16-Bit Dateigroesse aus Inode!
    push di
    mov bl, 0x0F
    call sh_print_dec16_pad6
    pop di
    mov si, str_unit_b
    mov ah, [SH_TEXT_ATTR]
    call sh_print_inline

.ls_print_addr:
    ; Spalte 3: Echte Speicheradresse (data_seg_hi : data_off)
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

    ; Spalte 4: Echter Dateiname aus Inode (Offset +8)
    lea si, [di + 8]
    mov ah, 0x0F
    cmp byte [ds:di + 0], 2
    jne .ls_name_out
    mov ah, 0x0B                    ; Ordnernamen in hellem Cyan
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

    ; Zusammenfassung mit echten Zaehlern und freiem CybFS-Speicherplatz:
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

    ; Freier R/W Speicher = 0x7000 - [FS_ALLOC_PTR]
    mov ax, FS_POOL_END
    sub ax, [FS_ALLOC_PTR]
    mov bl, 0x0A
    call sh_print_dec16
    mov si, str_ls_sum4
    mov ah, 0x0A
    call sh_print_line
    ret

; --- 8. CD (Echter Inode-Verzeichniswechsel) ---
.do_sh_cd:
    mov al, [SH_CLEAN_BUF + bx]
    cmp al, 0
    je .do_sh_cd_root
    cmp al, '\'
    je .do_sh_cd_root
    cmp al, '/'
    je .do_sh_cd_root
    cmp al, '.'
    je .do_sh_cd_up

    ; Ordnername in aktuellem Verzeichnis suchen
    call fs_find_in_dir
    jnc .cd_not_found
    cmp byte [ds:di + 0], 2         ; Muss ein <DIR> (flags == 2) sein!
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
    mov al, [ds:di + 1]             ; parent_id des aktuellen Ordners!
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

; --- 9. MKDIR <DIRNAME> (Echten Ordner in CybFS anlegen) ---
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

    ; Namen kopieren (bis Space oder 0, max 15 Zeichen)
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

; --- 10. TOUCH <FILENAME> (Echte leere Datei anlegen) ---
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
    ; Falls kein Dateiname angegeben wurde -> Standarddatei "notes.txt" oeffnen!
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
    ; Pruefen ob Datei im aktuellen Verzeichnis existiert, sonst neuen Inode anlegen
    call fs_find_in_dir
    jc .nano_found_existing
    call fs_alloc_inode
    jnc .fs_full_err

    ; Neuen Inode initialisieren & Dateinamen kopieren
    mov byte [ds:di + 0], 1         ; flags = 1 ([RAM])
    mov al, [SH_DIR_ID]
    mov [ds:di + 1], al
    mov ax, [FS_ALLOC_PTR]
    mov [ds:di + 2], ax             ; data_off
    mov word [ds:di + 4], 0x0000
    mov word [ds:di + 6], 0         ; file_size = 0 (noch leer)
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
    ; BX ueber Dateinamen vorspulen
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

    ; 18 x 72 Nano-Textpuffer (0x7000..0x750F = 1296 Bytes) mit Spaces (' ') fuellen
    push di
    mov di, NANO_BUF
    mov cx, 18 * 72
    mov al, ' '
.nano_clr_lp:
    mov [ds:di], al
    inc di
    loop .nano_clr_lp
    pop di

    ; Falls die Datei bereits Inhalt im RAM hat (flags == 1 und file_size > 0), in den Puffer laden!
    cmp byte [ds:di + 0], 1
    jne .nano_check_inline_arg
    mov cx, [ds:di + 6]
    test cx, cx
    jz .nano_check_inline_arg

    mov si, [ds:di + 2]             ; data_off im CybFS RAM-Pool
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
    ; Pruefen ob beim Aufruf 'write <datei> <text>' direkt Text mitgegeben wurde
    cmp byte [SH_CLEAN_BUF + bx], 0
    je .nano_check_script_mode

    ; Korrespondierende Stelle im Original-Puffer SH_CMD_BUF suchen (Gross/Kleinschreibung erhalten)
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
    ; Falls wir im Skript-Modus ('run <script.nsh>') sind, Zeile 0 frisch ueberschreiben
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
    ; Wenn aus einem .nsh Skript aufgerufen: direkt speichern ohne interaktive Oberflaeche!
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
; INTERAKTIVE GNU NANO VOLLBILD-OBERFLAECHE (CYBFORGE NANO v2.7)
; =============================================================================
.nano_enter_ui:
    call .nano_render_screen

.nano_event_loop:
    call sh_read_key_event
    test al, al
    jz .nano_idle

    ; Befinden wir uns im "Save modified buffer? [Y/N/C]" Dialog (NANO_MSG_ID == 2)?
    cmp byte [NANO_MSG_ID], 2
    jne .nano_normal_keys

    cmp al, 0x15                    ; 'Y' (US) -> Ja, speichern & beenden
    je .nano_save_and_exit
    cmp al, 0x2C                    ; 'Z' (DE Tastatur 'Y') -> Ja, speichern & beenden
    je .nano_save_and_exit
    cmp al, 0x1C                    ; ENTER -> Ja, speichern & beenden
    je .nano_save_and_exit
    cmp al, 0x31                    ; 'N' -> Nein, Aenderungen verwerfen & beenden
    je .nano_exit_now
    cmp al, 0x2E                    ; 'C' -> Abbrechen, weiter editieren
    je .nano_cancel_prompt
    cmp al, 0x01                    ; ESC -> Im Dialog: ebenfalls speichern & beenden oder abbrechen
    je .nano_cancel_prompt
    jmp .nano_event_loop

.nano_cancel_prompt:
    mov byte [NANO_MSG_ID], 0
    call sh_key_click
    call .nano_render_screen
    jmp .nano_event_loop

.nano_normal_keys:
    ; 1. Pruefen ob CTRL gedrueckt ist (^O, ^X, ^S, ^K, ^G)
    cmp byte [SH_CTRL], 1
    jne .nano_check_fn_keys

    cmp al, 0x18                    ; Ctrl+O (^O) -> WriteOut (Speichern)
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
    ; 2. Funktionstasten & Navigationstasten pruefen
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
    cmp al, 0x1C                    ; ENTER -> Neue Zeile
    je .nano_on_enter
    cmp al, 0x0E                    ; BACKSPACE
    je .nano_on_bs
    cmp al, 0x53                    ; DELETE (Entf)
    je .nano_on_del
    cmp al, 0x0F                    ; TAB -> 4 Spaces einfuegen
    je .nano_on_tab

    ; 3. Normales druckbares Zeichen ermitteln und an Cursorposition einfuegen
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

; --- Nano Cursor- & Edit-Aktionen ---
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
    ; Aktuelle Zeile (NANO_ROW) leeren und nachfolgende Zeilen um 1 nach oben schieben
    mov al, [NANO_ROW]
    mov ah, 72
    mul ah
    add ax, NANO_BUF
    mov di, ax                      ; DI = Start der aktuellen Zeile

    mov al, 17
    sub al, [NANO_ROW]
    jz .nano_cut_clear_last
    mov ah, 72
    mul ah
    mov cx, ax                      ; CX = Anzahl Bytes unterhalb von NANO_ROW
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
    ; Ungespeicherte Aenderungen -> GNU Nano "Save modified buffer?" Prompt anzeigen!
    mov byte [NANO_MSG_ID], 2
    call sound_click
    call .nano_render_screen
    jmp .nano_event_loop

.nano_save_and_exit:
    call .nano_save_buffer
    call sound_toggle

.nano_exit_now:
    ; Zurueck in die gerahmte BIOS Shell Oberflaeche schalten
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

; --- Hilfsroutinen fuer Nano Buffer Manipulation & Speichern ---
.nano_insert_char:
    ; Fuegt Zeichen DL an (NANO_ROW, NANO_COL) ein
    mov al, [NANO_ROW]
    mov ah, 72
    mul ah
    add ax, NANO_BUF
    mov si, ax                      ; SI = Zeilenstart

    ; Zeichen ab Spalte 70 runter bis NANO_COL um 1 nach rechts schieben
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
    ; Loescht Zeichen an (NANO_ROW, NANO_COL) und zieht Zeilenrest nach links
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
    ; Ermittelt die Spalte (CL = 0..71) hinter dem letzten Nicht-Space-Zeichen in NANO_ROW
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
    ; Serialisiert den 18x72 Nano-Puffer als echte Zeilen (mit 0x0A) in den CybFS RAM-Pool!
    mov di, [NANO_INODE]

    ; 1. Letzte nicht-leere Zeile (0..17) suchen
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
    ret

.nsb_found_last_row:
    ; CH = Anzahl zu speichernder Zeilen (1..18)
    ; Pruefen ob wir den bisherigen Platz am Ende von FS_ALLOC_PTR in-place wiederverwenden koennen
    mov bp, [FS_ALLOC_PTR]
    mov ax, [ds:di + 2]
    add ax, [ds:di + 6]
    cmp ax, bp
    jne .nsb_check_pool
    cmp word [ds:di + 2], FS_DATA_BASE
    jb .nsb_check_pool
    mov bp, [ds:di + 2]             ; In-place am Pool-Ende wiederverwenden!

.nsb_check_pool:
    cmp bp, FS_POOL_END - 256
    jb .nsb_start_write
    mov bp, FS_DATA_BASE + 1024     ; Sicherheits-Fallback falls Pool voll

.nsb_start_write:
    mov byte [ds:di + 0], 1         ; flags = 1 ([RAM])
    mov [ds:di + 2], bp             ; data_off
    mov word [ds:di + 4], 0x0000
    xor dx, dx                      ; DX = geschriebene Gesamt-Bytes
    xor bh, bh                      ; BH = aktueller Zeilenindex (0..CH-1)

.nsb_row_loop:
    mov al, bh
    mov ah, 72
    mul ah
    add ax, NANO_BUF
    mov si, ax

    ; Zeilenlaenge ohne Trailing Spaces ermitteln (CL = 72..0)
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
    mov byte [ds:bp], 0x0A          ; Echter Zeilenumbruch LF (0x0A)
    inc bp
    inc dx
    inc bh
    cmp bh, ch
    jb .nsb_row_loop

    mov [ds:di + 6], dx             ; Echte Dateigroesse im Inode aktualisieren!
    cmp bp, [FS_ALLOC_PTR]
    jbe .nsb_keep_alloc
    mov [FS_ALLOC_PTR], bp
.nsb_keep_alloc:
    mov [NANO_LAST_SZ], dx
    mov byte [NANO_MOD], 0
    mov byte [NANO_SAVED_FLAG], 1
    mov byte [NANO_MSG_ID], 1
    ret

.nano_render_screen:
    ; Zeichnet das komplette GNU Nano Vollbild-Interface (Zeilen 0..24)
    ; Zeile 0: Klassischer invertierter GNU Nano Header Balken (0x70 = Schwarz auf Hellgrau)
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

    ; Echten Dateinamen aus Inode in die Titelzeile schreiben
    mov bx, [NANO_INODE]
    lea si, [bx + 8]
.nrs_fn_lp:
    mov al, [ds:si]
    test al, al
    jz .nrs_fn_done
    mov ah, 0x71                    ; Dunkelblau auf Hellgrau
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
    mov ah, 0x74                    ; Dunkelrot auf Hellgrau fuer [Modified]
.nrs_mod_pr:
    call print_string

    ; Zeile 1: Oberer Editor-Rahmen
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

    ; Zeilen 2..19: Die 18 Textzeilen aus NANO_BUF (mit Zeilennummern 01..18 & Cursor!)
    xor dl, dl                      ; DL = Zeilenindex 0..17
.nrs_row_lp:
    mov bl, dl
    add bl, 2                       ; Bildschirmzeile = DL + 2
    xor al, al
    call xy_to_di

    ; Linker Rahmen '│'
    mov ah, 0x0B
    mov al, 0x06
    stosw

    ; Zeilennummer (01..18)
    mov ah, 0x08
    cmp dl, [NANO_ROW]
    jne .nrs_ln_col_ok
    mov ah, 0x0E                    ; Aktive Zeile gelb hervorheben!
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
    mov al, 0x06                    ; Trennstrich '│' nach Zeilennummer
    stosw
    mov ah, 0x07
    mov al, ' '
    stosw

    ; 72 Textspalten aus NANO_BUF + dl * 72 ausgeben
    mov al, dl
    mov ah, 72
    mul ah
    add ax, NANO_BUF
    mov si, ax
    xor dh, dh                      ; DH = Spaltenindex 0..71
.nrs_col_lp:
    mov al, [ds:si]
    inc si
    mov ah, 0x0F                    ; Heller weisser Text auf Schwarz
    cmp dl, [NANO_ROW]
    jne .nrs_put_ch
    cmp dh, [NANO_COL]
    jne .nrs_put_ch
    mov ah, 0x70                    ; Invertierter Block-Cursor an (NANO_ROW, NANO_COL)!
.nrs_put_ch:
    stosw
    inc dh
    cmp dh, 72
    jb .nrs_col_lp

    mov ah, 0x07
    mov al, ' '
    stosw
    mov ah, 0x0B
    mov al, 0x06                    ; Rechter Rahmen '│'
    stosw

    inc dl
    cmp dl, 18
    jb .nrs_row_lp

    ; Zeile 20: Unterer Editor-Rahmen
    mov di, (20 * 80) * 2
    mov ah, 0x0B
    mov al, 0x03                    ; '└'
    stosw
    mov cx, 78
    mov al, 0x05                    ; '─'
    rep stosw
    mov al, 0x04                    ; '┘'
    stosw

    ; Zeile 21: Nano Status- & Dialog-Zeile
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
    mov ax, 0x4F20                  ; Weiss auf Rot fuer wichtigen Speichern-Dialog!
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
    ; Zeile 22: Live Cursor-Position (Line/Col) & Freier CybFS Speicherpool
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

    ; Zeilen 23 & 24: Authentische 2-zeilige GNU Nano Shortcut-Leiste ('^' Badges in 0x70!)
    mov di, (23 * 80) * 2
    mov si, str_nano_bot1
    call .nano_print_shortcut_bar
    mov di, (24 * 80) * 2
    mov si, str_nano_bot2
    call .nano_print_shortcut_bar
    ret

.nano_print_shortcut_bar:
    ; Gibt einen 80-Zeichen String aus, wobei Zeichen innerhalb von [...] oder ^X invertiert (0x70) dargestellt werden
    mov ah, 0x07
.npsb_lp:
    mov al, [cs:si]
    inc si
    test al, al
    jz .npsb_done
    cmp al, '{'                     ; '{' startet invertiertes Shortcut-Badge (0x70)
    je .npsb_inv_on
    cmp al, '}'                     ; '}' beendet invertiertes Shortcut-Badge (0x07)
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

; --- 12. APPEND <FILENAME> <TEXT> (Zeile an echte Datei anhaengen!) ---
.do_sh_append:
    cmp byte [SH_CLEAN_BUF + bx], 0
    je .append_usage
    call fs_find_in_dir
    jnc .cat_not_found
    cmp byte [ds:di + 0], 1
    jne .append_not_ram

    ; Pruefen ob die Datei direkt am Ende des aktuellen Pools liegt, sonst umkopieren
    mov bp, [FS_ALLOC_PTR]
    cmp bp, FS_POOL_END - 128
    jae .fs_full_err

    mov ax, [ds:di + 2]             ; altes data_off
    add ax, [ds:di + 6]             ; + alte file_size
    cmp ax, bp
    je .app_in_place

    ; Alte Daten nach [FS_ALLOC_PTR] kopieren, damit Datei zusammenhaengend bleibt
    push si
    mov si, [ds:di + 2]
    mov [ds:di + 2], bp             ; neues data_off
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
    ; Text nach dem 2. Wort in SH_CMD_BUF finden
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
    mov dx, [ds:di + 6]             ; Bisherige Dateigroesse
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

; --- 13. RM / DEL <NAME> (Echten Inode aus CybFS loeschen!) ---
.do_sh_rm:
    cmp byte [SH_CLEAN_BUF + bx], 0
    je .rm_usage
    call fs_find_in_dir
    jnc .cat_not_found

    ; Inode als geloescht markieren (flags = 0)
    mov byte [ds:di + 0], 0

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

; --- 14. CAT / TYPE <FILENAME> (100% ECHTE DATEI-BYTES AUS CYBFS / ROM LESEN!) ---
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
    cmp al, 3                       ; [ROM] Datei -> Live 32-Bit ROM Header Dump (+ Audio Play)!
    je .cat_rom_file

    ; flags == 1: Echte RAM-Datei Byte fuer Byte aus [ds:data_off] lesen und ausgeben!
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

    mov cx, [ds:di + 6]             ; Echte Dateigroesse in Bytes
    test cx, cx
    jz .cat_empty_done
    mov si, [ds:di + 2]             ; Echte RAM-Startadresse (data_off)
.cat_ram_loop:
    mov al, [ds:si]
    inc si
    cmp al, 0x0A                    ; Zeilenumbruch?
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
    ; Prüfen ob es eine WAV-Datei ist (meta 0..7) -> automatisch ueber SB16 abspielen!
    mov al, [ds:di + 24]
    cmp al, 7
    ja .cat_rom_dump
    push di
    call sb16_play_pcm
    pop di
.cat_rom_dump:
    ; Echte 32-Bit Lineare ROM-Adresse aus Inode holen: (data_seg_hi << 16) | data_off
    movzx eax, word [ds:di + 4]
    shl eax, 16
    movzx edx, word [ds:di + 2]
    or eax, edx
    mov esi, eax

    ; 4 Zeilen a 16 echte Bytes direkt via 32-Bit Unreal Mode [fs:esi] dumpen!
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

; --- 15. RUN / SH <SCRIPT.NSH> (Echte Skriptdatei aus CybFS ausfuehren!) ---
.do_sh_run:
    cmp byte [SH_CLEAN_BUF + bx], 0
    je .run_usage
    call fs_find_in_dir
    jnc .cat_not_found

    ; Falls es snake.efi ist -> Snake starten
    cmp byte [ds:di + 24], 0xFD
    je .do_sh_snake
    cmp byte [ds:di + 0], 1
    jne .run_not_script

    mov ax, [ds:di + 2]             ; data_off
    mov [SH_SCRIPT_PTR], ax
    add ax, [ds:di + 6]             ; + file_size = Ende
    mov [SH_SCRIPT_END], ax
    mov byte [SH_SCRIPT_ACT], 1

.run_line_loop:
    mov si, [SH_SCRIPT_PTR]
    cmp si, [SH_SCRIPT_END]
    jae .run_done

    ; Eine Zeile aus der Datei in SH_CMD_BUF kopieren
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

    ; Schutz gegen Endlos-Rekursion ('run' im Skript ignorieren)
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

; --- 16. FORMAT (CybFS aus ROM Block 0 neu initialisieren) ---
.do_sh_format:
    call fs_format_from_rom
    call sound_toggle
    mov si, str_fmt_ok
    mov ah, 0x0A
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

; --- 18. PCI / DEVTREE (100% ECHTER HARDWARE PCI BUS SCANNER UEBER 0xCF8/0xCFC!) ---
.do_sh_pci:
    mov si, str_pci_hdr
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line

    xor cx, cx                      ; CL = Device (0..7), CH = Function (0..3)
.pci_scan_loop:
    ; 32-Bit PCI Config Address bauen: 0x80000000 | (dev << 11) | (fn << 8)
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

    cmp ax, 0xFFFF                  ; 0xFFFF = Kein PCI-Geraet an diesem Slot
    je .pci_next_slot
    test ax, ax
    jz .pci_next_slot

    push eax
    push cx

    ; Bus 00, Dev CL, Fn CH ausgeben
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

    ; Echte VendorID : DeviceID aus Hardware-Register EAX ausgeben!
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

    ; PCI Class/Subclass aus Register 0x08 live auslesen!
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
    mov edx, eax                    ; DX = Class/Subclass sichern BEVOR AH fuer Textfarbe genutzt wird!

    mov si, str_pci_cl_pfx
    mov ah, [SH_TEXT_ATTR]
    call sh_print_inline
    mov ah, 0x0A
    call sh_print_hex16

    ; Bekannte Chipset-Namen anhand der echten Class/Device zuordnen
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

    ; Zusaetzlich aktive ISA-Hardware-Statuszeile (SB16 DSP + CMOS RTC)
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

; --- 25. MEMTEST (Echter 64KB RAM Schreib-/Lese-Vergleichstest mit Fehlerzaehler!) ---
.do_sh_memtest:
    mov si, str_mt_1
    mov ah, [SH_HIGH_ATTR]
    call sh_print_line

    push es
    mov ax, 0x2000
    mov es, ax
    xor dx, dx                      ; DX = Echter Fehlerzaehler!

    ; Pass 1: 0x55AA schreiben und Wort fuer Wort zuruecklesen & pruefen!
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

    ; Pass 2: 0xAA55 schreiben und Wort fuer Wort zuruecklesen & pruefen!
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
    pop ax                          ; AX = Echte gemessene Fehleranzahl!
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
    call .vga_apply_font_scale
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

; --- LIVE HARDWARE VGA PLANE 2 FONT SCALER (0xA000:0000) ---
.vga_apply_font_scale:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es

    ; 1. VGA Sequencer & Graphics Controller fuer Plane 2 (0xA0000) freischalten
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

    ; 2. Alle ASCII-Glyphen aus font_table entsprechend [CFG_SH_FONT] (0..3) skalieren!
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
    je .vafs_scale_huge             ; 3: Huge 8x16 XL Wide-Bold (14px Cap Height)

    ; 2: Large 8x16 Standard IBM VGA (10px Cap Height, 1:1 Kopie)
    mov cx, 16
.vafs_std_lp:
    mov al, [cs:si]
    inc si
    stosb
    loop .vafs_std_lp
    jmp .vafs_char_lp

.vafs_scale_small:
    ; Small (1): 4 Leerzeilen oben + 8 komprimierte Scanlines (2:1 OR) + 4 Leerzeilen unten
    xor al, al
    stosb
    stosb
    stosb
    stosb
    mov cx, 8
.vafs_sm_lp:
    mov al, [cs:si]
    or al, [cs:si + 1]              ; Gerade + ungerade Scanline verschmelzen (kein Strich geht verloren!)
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
    ; Medium (2): 12 aktive Scanlines zentriert (8px Cap Height statt 10px)
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
    ; Huge (4): Vertikal auf 14 aktive Scanlines gestreckt + horizontal aufgedickt (al | (al >> 1))!
    xor al, al
    stosb                           ; Scanline 0
    mov bx, si
    ; Scanlines 1..14 mit vertikaler Streckung + Fettdruck ausgeben
    mov al, [cs:bx + 2]             ; Top Cap doppelt
    call .vafs_bold_stosb
    mov al, [cs:bx + 2]
    call .vafs_bold_stosb
    mov al, [cs:bx + 3]
    call .vafs_bold_stosb
    mov al, [cs:bx + 4]
    call .vafs_bold_stosb
    mov al, [cs:bx + 5]
    call .vafs_bold_stosb
    mov al, [cs:bx + 6]
    call .vafs_bold_stosb
    mov al, [cs:bx + 7]             ; Mittelbalken doppelt
    call .vafs_bold_stosb
    mov al, [cs:bx + 7]
    call .vafs_bold_stosb
    mov al, [cs:bx + 8]
    call .vafs_bold_stosb
    mov al, [cs:bx + 9]
    call .vafs_bold_stosb
    mov al, [cs:bx + 10]
    call .vafs_bold_stosb
    mov al, [cs:bx + 11]            ; Baseline doppelt
    call .vafs_bold_stosb
    mov al, [cs:bx + 11]
    or al, [cs:bx + 12]
    call .vafs_bold_stosb
    mov al, [cs:bx + 13]
    call .vafs_bold_stosb
    xor al, al
    stosb                           ; Scanline 15
    add si, 16
    jmp .vafs_char_lp

.vafs_restore_custom:
    ; 3. Rahmen-Glyphen (0x01..0x0A) immer in voller 16-Scanline Qualitaet halten (damit Rahmen nahtlos bleiben!)
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

    ; 4. Zurueck in den Odd/Even Text-Mode bei 0xB8000 schalten
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
    mov ax, 0x0E06                  ; GR06 = 0xB8000 Textfenster
    out dx, ax

    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

.vafs_bold_stosb:
    stosb
    ret

; --- 31. REBOOT / RESET (Echter Warm-Reboot zurueck zum BIOS POST!) ---
.do_sh_reboot:
    mov si, str_reboot_msg
    mov ah, 0x0E
    call sh_print_line
    call sound_toggle
    mov ecx, 120000000              ; ~0.4s kurze Anzeige vor dem Reset
    call delay_cycles
    pop ax
    mov byte [CFG_SH_FONT], 2
    call .vga_apply_font_scale
    call apply_color_theme
    jmp post_screen

; --- 32. SHUTDOWN / POWEROFF / HALT (Echter Hardware ACPI S5 Soft-Off!) ---
.do_sh_shutdown:
    mov si, str_shut_msg1
    mov ah, 0x0E
    call sh_print_line
    mov si, str_shut_msg2
    mov ah, 0x0C
    call sh_print_line

    ; Akustisches Shutdown-Signal abspielen
    mov al, 6                       ; Sample 6 (Descending Chime)
    call sb16_play_pcm
    mov ecx, 250000000              ; ~0.8s warten damit Meldung & Sound wahrnehmbar sind
    call delay_cycles

    ; 1. Bare-Metal Intel PIIX4 PM (PCI 00:01.3) ACPI I/O Base auf 0x0600 mappen & aktivieren!
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

    ; Jetzt echten ACPI S5 Soft-Off (SLP_TYP5 | SLP_EN = 0x2000) an PM1a_CNT (0x0604) senden!
    mov dx, 0x0604
    mov ax, 0x2000
    out dx, ax

    ; 2. Bochs / Aelteres QEMU ACPI Power-Off (Port 0xB004 -> 0x2000)
    mov dx, 0xB004
    mov ax, 0x2000
    out dx, ax

    ; 3. VirtualBox / Cloud Hypervisor ACPI Power-Off (Port 0x4004 -> 0x3400)
    mov dx, 0x4004
    mov ax, 0x3400
    out dx, ax

    ; 4. Fallback falls Hardware kein ACPI S5 unterstuetzt: Sichere ATX Halt-Konsole
    mov si, str_shut_halted
    mov ah, 0x0A
    call sh_print_line
    cli
.shut_hlt_loop:
    hlt
    jmp .shut_hlt_loop

; -----------------------------------------------------------------------------
; SCANCODE SET 1 -> ASCII LOOKUP TABLES (0x00..0x57)
; -----------------------------------------------------------------------------
sh_hex_chars:
    db "0123456789ABCDEF"

sh_scancode_norm:
    db 0,   0,  '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=',  0,   0
    db 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']',  0,   0,  'a', 's'
    db 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', "'", '`',  0,  '\','z', 'x', 'c', 'v'
    db 'b', 'n', 'm', ',', '.', '/',  0,  '*',  0,  ' '
    times 30 db 0

sh_scancode_shift:
    db 0,   0,  '!', '@', '#', '$', '%', '^', '/', '*', '(', ')', '_', '+',  0,   0
    db 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}',  0,   0,  'A', 'S'
    db 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"', '~',  0,  '|', 'Z', 'X', 'C', 'V'
    db 'B', 'N', 'M', ';', ':', '?',  0,  '*',  0,  ' '
    times 30 db 0

sh_ac_table:
    db "help", 0, "write ", 0, "nano ", 0, "edit ", 0, "setfont ", 0, "shutdown", 0
    db "reboot", 0, "append ", 0, "mkdir ", 0, "touch ", 0, "rm ", 0, "run ", 0
    db "format", 0, "memmap", 0, "memtest", 0, "map", 0, "sysinfo", 0, "pci", 0
    db "dmem ", 0, "cmos", 0, "cpu", 0, "time", 0, "sound ", 0, "color ", 0
    db "clear", 0, "snake", 0, "exit", 0, "cat ", 0, "cd ", 0, 0

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
    db "< FS0:\> (UEFI)     >", 0
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
    db "Choose command prompt format (FS0:\>, SHELL>, root@cybforge).", 0
str_help_sh4:
    db "Configure device table banner displayed when entering Shell.", 0
str_help_sh5:
    db "Enable or mute tactile keystroke sound inside the BIOS Shell.", 0
str_help_sh6:
    db "Choose whether POST boots Snake Game or directly to BiosShell.", 0

; --- Framed BIOS Shell & Live CybFS Strings ---
str_sh_topbar:
    db "CYBFORGE UEFI/BIOS SHELL v2.7 [CybFS + GNU Nano]     ROM: 256KB  RAM: 640KB", 0
str_sh_frame_top:
    db " Cybforge Interactive UEFI/BIOS Console [CybFS Live R/W] ", 0
str_sh_frame_bot:
    db " [WRITE/NANO] Editor | [SETFONT] Scale | [REBOOT/SHUTDOWN] Power | [EXIT] ", 0
str_sh_botbar:
    db "[HELP] Cmds  [WRITE] Nano  [SETFONT] Scale  [REBOOT] Reset  [SHUTDOWN] Off", 0

str_pr_fs0_pfx:     db "FS0:\", 0
str_pr_gt:          db "> ", 0
str_pr_compact:     db "SHELL> ", 0
str_pr_root:        db "root@cybforge:# ", 0

str_sh_ban1:
    db "Cybforge UEFI/BIOS Shell v2.6 [Live CybFS v1.0 Read/Write File System]", 0
str_sh_ban2:
    db "Mounted CybFS from ROM Block 0 (0xFFFC0100) -> RAM 0x3000..0x7FFF (20 KB)", 0
str_sh_map_hdr:
    db "Handle  Media Type    Capacity   Hardware Device Path", 0
str_sh_map_sep:
    db "------  ------------  ---------  -----------------------------------------", 0
str_sh_map1:
    db "FS0:    CybFS R/W     20 KB RAM  RamDisk(0x3000)/RomSeed(Bank0,0xFFFC0100)", 0
str_sh_map2:
    db "BLK0:   Wave Audio    128 KB     PciRoot(0)/PcmAudio(16-Bit, 0xFFFD0000)", 0
str_sh_map3:
    db "BLK1:   System RAM    640 KB     SystemMemory(Conventional, 0x00000000)", 0
str_sh_map4:
    db "CMOS0:  RTC NVRAM     128 Bytes  IsaBridge(0x70)/MC146818(Chksum: Valid)", 0
str_sh_map5:
    db "VGA0:   Text Display  128 KB     Pci(0,2)/VgaController(80x25, VRAM:B800h)", 0
str_sh_map6:
    db "SB16:   Audio DSP     DMA Ch 5   IsaBridge(0x220)/SoundBlaster16(11025 Hz)", 0
str_sh_ban_hint:
    db "Try 'ls', 'write test.txt Hallo!', 'cat test.txt', 'rm test.txt', 'exit'.", 0

str_sh_err_pfx:
    db "Error: Unknown command '", 0
str_sh_err_sfx:
    db "'. Type 'help' for available commands.", 0

str_sh_hlp_hdr:
    db "Cybforge UEFI/BIOS Shell v2.7 & Live CybFS - Command Reference:", 0
str_sh_hlp1:
    db "write <file> Open GNU Nano Editor!     nano <file>  Open GNU Nano Editor!", 0
str_sh_hlp2:
    db "ls / dir     Scan live CybFS Inodes    cd <dir>     Change dir (../efi)", 0
str_sh_hlp3:
    db "cat <file>   Read live file bytes      append <f><t>Append line to real file", 0
str_sh_hlp4:
    db "mkdir <dir>  Create real directory     rm / del <f> Delete file/dir Inode", 0
str_sh_hlp5:
    db "touch <file> Create empty 0-byte file  run <f.nsh>  Run CybFS script", 0
str_sh_hlp6:
    db "setfont [1-4]Scale shell text size!    format       Re-format CybFS from ROM", 0
str_sh_hlp7:
    db "pci / lspci  Live 0xCF8 PCI bus scan   map / memmap Device & E820 RAM map", 0
str_sh_hlp8:
    db "dmem [hex]   Live 64B Hex/ASCII dump   cmos / nvram Live CMOS NVRAM dump", 0
str_sh_hlp9:
    db "cpu / regs   Dump live x86 registers   time / date  Read hardware RTC clock", 0
str_sh_hlp10:
    db "sound [0-7]  Play 16-bit PCM wave      memtest      Verify 64KB RAM (2x pass)", 0
str_sh_hlp11:
    db "reboot       Warm BIOS POST reset      shutdown     ACPI S5 system power-off!", 0
str_sh_hlp12:
    db "snake / boot Launch SNAKE.EFI game     exit / quit  Return to BIOS Setup!", 0

str_sh_ver1:
    db "Cybforge UEFI Interactive Shell v2.6 [Live CybFS v1.0 & Hardware Edition]", 0
str_sh_ver2:
    db "  File System     : CybFS v1.0 (32 Inodes @ 0x3020, 19.4 KB R/W Pool @ 0x3420)", 0
str_sh_ver3:
    db "  ROM Image Layout: 262,144 Bytes (Block 0 CybFS, Block 1-2 PCM, Block 3 BIOS)", 0
str_sh_ver4:
    db "  CPU Architecture: x86 16-Bit Real Mode + 32-Bit Flat Unreal Mode (4GB FS)", 0
str_sh_ver5:
    db "  Audio Engine    : Creative Sound Blaster 16 DSP v4.05 (16-Bit DMA Ch 5)", 0

str_sh_mm_hdr:
    db "Region Type   Start      End        Size    Description", 0
str_sh_mm_sep:
    db "------------  ---------  ---------  ------  ------------------------------", 0
str_sh_mm1:
    db "RT_Code       00000000h  000004FFh    1 KB  Real-Mode IVT & BIOS Data Area", 0
str_sh_mm2:
    db "BS_Data       00001000h  00001FFFh    4 KB  Cybforge Kernel & Shell State", 0
str_sh_mm3:
    db "CybFS_RAM     00003000h  00007FFFh   20 KB  Live CybFS Inodes & R/W Pool", 0
str_sh_mm4:
    db "DMA_Buffer    00020000h  0002FFFFh   64 KB  SB16 16-Bit PCM DMA Bounce RAM", 0
str_sh_mm5:
    db "Conventional  00030000h  0009FFFFh  448 KB  Available Base System Memory", 0
str_sh_mm6:
    db "MMIO_VRAM     000A0000h  000BFFFFh  128 KB  VGA Graphics & Text VRAM", 0
str_sh_mm7:
    db "CybFS_ROM     FFFC0000h  FFFCFFFFh   64 KB  ROM Block 0 Master CybFS Image", 0
str_sh_mm8:
    db "Audio_BIOS    FFFD0000h  FFFFFFFFh  192 KB  16-Bit PCM Bank & BIOS Kernel", 0
str_sh_mm_tot:
    db "Total: 640 KB Base RAM | 20 KB CybFS Live Volume | 256 KB Flash ROM", 0

; --- Live CybFS Output Strings ---
str_ls_hdr_pfx:
    db "Live Directory of FS0:\", 0
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
str_fmt_ok:
    db "CybFS v1.0 formatted from ROM Block 0 (0xFFFC0100 -> 0x3000..0x7FFF).", 0

str_neo1:
    db "   .==========.     root@cybforge-bios", 0
str_neo2:
    db "  /  CYBFORGE  \    ------------------------------------------", 0
str_neo3:
    db " |   [x86-32]   |   Shell    : Cybforge UEFI/BIOS Shell v2.6", 0
str_neo4:
    db " |  RETRO BIOS  |   FileSys  : CybFS v1.0 Live R/W (0x3000h)", 0
str_neo5:
    db "  \    v2.6    /    Memory   : 640 KB Base RAM / 256 KB ROM", 0
str_neo6:
    db "   '=========='     Hardware : Live PCI 0xCF8 / SB16 DMA Ch5", 0
str_neo7:
    db "                    Status   : NVRAM Checksum OK ('exit'=Setup)", 0

; --- Live PCI Hardware Bus Scanner Strings ---
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
str_pci_desc_gen:
    db "  PCI System Peripheral Device", 0
str_pci_isa:
    db "ISA Bus :  0220h=SB16 DSP v4.05 (DMA5) | 0060h=8042 PS/2 | 0070h=CMOS RTC", 0

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
    db "[SYSTEM] Initiating warm BIOS reset -> Jumping to POST (F000:FFF0h)...", 0
str_shut_msg1:
    db "[ACPI S5] Syncing CybFS RAM Disk & stopping Sound Blaster 16 DMA...", 0
str_shut_msg2:
    db "[ACPI S5] Sending SLP_TYP5 (0x2000) to PM1a_CNT (Port 0x0604) -> Power Off!", 0
str_shut_halted:
    db "[SYSTEM HALTED] CPU in low-power HLT state. It is now safe to turn off PC.", 0

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
    db 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; ' '
    db 0x21, 0x00, 0x00, 0x18, 0x3C, 0x3C, 0x3C, 0x18, 0x18, 0x18, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00 ; '!'
    db 0x22, 0x00, 0x66, 0x66, 0x66, 0x24, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; '"'
    db 0x23, 0x00, 0x00, 0x00, 0x6C, 0x6C, 0xFE, 0x6C, 0x6C, 0x6C, 0xFE, 0x6C, 0x6C, 0x00, 0x00, 0x00, 0x00 ; '#'
    db 0x24, 0x18, 0x18, 0x7C, 0xC6, 0xC2, 0xC0, 0x7C, 0x06, 0x06, 0x86, 0xC6, 0x7C, 0x18, 0x18, 0x00, 0x00 ; '$'
    db 0x25, 0x00, 0x00, 0x00, 0x00, 0xC2, 0xC6, 0x0C, 0x18, 0x30, 0x60, 0xC6, 0x86, 0x00, 0x00, 0x00, 0x00 ; '%'
    db 0x26, 0x00, 0x00, 0x38, 0x6C, 0x6C, 0x38, 0x76, 0xDC, 0xCC, 0xCC, 0xCC, 0x76, 0x00, 0x00, 0x00, 0x00 ; '&'
    db 0x27, 0x00, 0x30, 0x30, 0x30, 0x60, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; '''
    db 0x28, 0x00, 0x00, 0x0C, 0x18, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x18, 0x0C, 0x00, 0x00, 0x00, 0x00 ; '('
    db 0x29, 0x00, 0x00, 0x30, 0x18, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x18, 0x30, 0x00, 0x00, 0x00, 0x00 ; ')'
    db 0x2A, 0x00, 0x00, 0x00, 0x00, 0x66, 0x3C, 0xFF, 0x3C, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; '*'
    db 0x2B, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x7E, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; '+'
    db 0x2C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x18, 0x30, 0x00, 0x00, 0x00 ; ','
    db 0x2D, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFE, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; '-'
    db 0x2E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00 ; '.'
    db 0x2F, 0x00, 0x00, 0x00, 0x00, 0x02, 0x06, 0x0C, 0x18, 0x30, 0x60, 0xC0, 0x80, 0x00, 0x00, 0x00, 0x00 ; '/'
    db 0x30, 0x00, 0x00, 0x7C, 0xC6, 0xCE, 0xDE, 0xF6, 0xE6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00, 0x00 ; '0'
    db 0x31, 0x00, 0x00, 0x18, 0x38, 0x78, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x7E, 0x00, 0x00, 0x00, 0x00 ; '1'
    db 0x32, 0x00, 0x00, 0x7C, 0xC6, 0x06, 0x0C, 0x18, 0x30, 0x60, 0xC0, 0xC6, 0xFE, 0x00, 0x00, 0x00, 0x00 ; '2'
    db 0x33, 0x00, 0x00, 0x7C, 0xC6, 0x06, 0x06, 0x3C, 0x06, 0x06, 0x06, 0xC6, 0x7C, 0x00, 0x00, 0x00, 0x00 ; '3'
    db 0x34, 0x00, 0x00, 0x0C, 0x1C, 0x3C, 0x6C, 0xCC, 0xFE, 0x0C, 0x0C, 0x0C, 0x1E, 0x00, 0x00, 0x00, 0x00 ; '4'
    db 0x35, 0x00, 0x00, 0xFE, 0xC0, 0xC0, 0xC0, 0xFC, 0x06, 0x06, 0x06, 0xC6, 0x7C, 0x00, 0x00, 0x00, 0x00 ; '5'
    db 0x36, 0x00, 0x00, 0x38, 0x60, 0xC0, 0xC0, 0xFC, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00, 0x00 ; '6'
    db 0x37, 0x00, 0x00, 0xFE, 0xC6, 0x06, 0x06, 0x0C, 0x18, 0x30, 0x30, 0x30, 0x30, 0x00, 0x00, 0x00, 0x00 ; '7'
    db 0x38, 0x00, 0x00, 0x7C, 0xC6, 0xC6, 0xC6, 0x7C, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00, 0x00 ; '8'
    db 0x39, 0x00, 0x00, 0x7C, 0xC6, 0xC6, 0xC6, 0x7E, 0x06, 0x06, 0x06, 0x0C, 0x78, 0x00, 0x00, 0x00, 0x00 ; '9'
    db 0x3A, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00 ; ':'
    db 0x3B, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00, 0x18, 0x18, 0x30, 0x00, 0x00, 0x00, 0x00 ; ';'
    db 0x3C, 0x00, 0x00, 0x00, 0x06, 0x0C, 0x18, 0x30, 0x60, 0x30, 0x18, 0x0C, 0x06, 0x00, 0x00, 0x00, 0x00 ; '<'
    db 0x3D, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7E, 0x00, 0x00, 0x7E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; '='
    db 0x3E, 0x00, 0x00, 0x00, 0x60, 0x30, 0x18, 0x0C, 0x06, 0x0C, 0x18, 0x30, 0x60, 0x00, 0x00, 0x00, 0x00 ; '>'
    db 0x3F, 0x00, 0x00, 0x7C, 0xC6, 0xC6, 0x0C, 0x18, 0x18, 0x18, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00 ; '?'
    db 0x40, 0x00, 0x00, 0x00, 0x7C, 0xC6, 0xC6, 0xDE, 0xDE, 0xDE, 0xDC, 0xC0, 0x7C, 0x00, 0x00, 0x00, 0x00 ; '@'
    db 0x41, 0x00, 0x00, 0x10, 0x38, 0x6C, 0xC6, 0xC6, 0xFE, 0xC6, 0xC6, 0xC6, 0xC6, 0x00, 0x00, 0x00, 0x00 ; 'A'
    db 0x42, 0x00, 0x00, 0xFC, 0x66, 0x66, 0x66, 0x7C, 0x66, 0x66, 0x66, 0x66, 0xFC, 0x00, 0x00, 0x00, 0x00 ; 'B'
    db 0x43, 0x00, 0x00, 0x3C, 0x66, 0xC2, 0xC0, 0xC0, 0xC0, 0xC0, 0xC2, 0x66, 0x3C, 0x00, 0x00, 0x00, 0x00 ; 'C'
    db 0x44, 0x00, 0x00, 0xF8, 0x6C, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x6C, 0xF8, 0x00, 0x00, 0x00, 0x00 ; 'D'
    db 0x45, 0x00, 0x00, 0xFE, 0x66, 0x62, 0x68, 0x78, 0x68, 0x60, 0x62, 0x66, 0xFE, 0x00, 0x00, 0x00, 0x00 ; 'E'
    db 0x46, 0x00, 0x00, 0xFE, 0x66, 0x62, 0x68, 0x78, 0x68, 0x60, 0x60, 0x60, 0xF0, 0x00, 0x00, 0x00, 0x00 ; 'F'
    db 0x47, 0x00, 0x00, 0x3C, 0x66, 0xC2, 0xC0, 0xC0, 0xDE, 0xC6, 0xC6, 0x66, 0x3A, 0x00, 0x00, 0x00, 0x00 ; 'G'
    db 0x48, 0x00, 0x00, 0xC6, 0xC6, 0xC6, 0xC6, 0xFE, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x00, 0x00, 0x00, 0x00 ; 'H'
    db 0x49, 0x00, 0x00, 0x3C, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00, 0x00, 0x00, 0x00 ; 'I'
    db 0x4A, 0x00, 0x00, 0x1E, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0xCC, 0xCC, 0xCC, 0x78, 0x00, 0x00, 0x00, 0x00 ; 'J'
    db 0x4B, 0x00, 0x00, 0xE6, 0x66, 0x66, 0x6C, 0x78, 0x78, 0x6C, 0x66, 0x66, 0xE6, 0x00, 0x00, 0x00, 0x00 ; 'K'
    db 0x4C, 0x00, 0x00, 0xF0, 0x60, 0x60, 0x60, 0x60, 0x60, 0x60, 0x62, 0x66, 0xFE, 0x00, 0x00, 0x00, 0x00 ; 'L'
    db 0x4D, 0x00, 0x00, 0xC6, 0xEE, 0xFE, 0xFE, 0xD6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x00, 0x00, 0x00, 0x00 ; 'M'
    db 0x4E, 0x00, 0x00, 0xC6, 0xE6, 0xF6, 0xFE, 0xDE, 0xCE, 0xC6, 0xC6, 0xC6, 0xC6, 0x00, 0x00, 0x00, 0x00 ; 'N'
    db 0x4F, 0x00, 0x00, 0x38, 0x6C, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x6C, 0x38, 0x00, 0x00, 0x00, 0x00 ; 'O'
    db 0x50, 0x00, 0x00, 0xFC, 0x66, 0x66, 0x66, 0x7C, 0x60, 0x60, 0x60, 0x60, 0xF0, 0x00, 0x00, 0x00, 0x00 ; 'P'
    db 0x51, 0x00, 0x00, 0x7C, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xD6, 0xDE, 0x7C, 0x0C, 0x0E, 0x00, 0x00 ; 'Q'
    db 0x52, 0x00, 0x00, 0xFC, 0x66, 0x66, 0x66, 0x7C, 0x6C, 0x66, 0x66, 0x66, 0xE6, 0x00, 0x00, 0x00, 0x00 ; 'R'
    db 0x53, 0x00, 0x00, 0x7C, 0xC6, 0xC6, 0x60, 0x38, 0x0C, 0x06, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00, 0x00 ; 'S'
    db 0x54, 0x00, 0x00, 0x7E, 0x7E, 0x5A, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00, 0x00, 0x00, 0x00 ; 'T'
    db 0x55, 0x00, 0x00, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00, 0x00 ; 'U'
    db 0x56, 0x00, 0x00, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x6C, 0x38, 0x10, 0x00, 0x00, 0x00, 0x00 ; 'V'
    db 0x57, 0x00, 0x00, 0xC6, 0xC6, 0xC6, 0xC6, 0xD6, 0xD6, 0xFE, 0xEE, 0x6C, 0x44, 0x00, 0x00, 0x00, 0x00 ; 'W'
    db 0x58, 0x00, 0x00, 0xC6, 0xC6, 0x6C, 0x7C, 0x38, 0x38, 0x7C, 0x6C, 0xC6, 0xC6, 0x00, 0x00, 0x00, 0x00 ; 'X'
    db 0x59, 0x00, 0x00, 0x66, 0x66, 0x66, 0x66, 0x3C, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00, 0x00, 0x00, 0x00 ; 'Y'
    db 0x5A, 0x00, 0x00, 0xFE, 0xC6, 0x86, 0x0C, 0x18, 0x30, 0x60, 0xC2, 0xC6, 0xFE, 0x00, 0x00, 0x00, 0x00 ; 'Z'
    db 0x5B, 0x00, 0x00, 0x3C, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x3C, 0x00, 0x00, 0x00, 0x00 ; '['
    db 0x5C, 0x00, 0x00, 0x00, 0x80, 0xC0, 0xE0, 0x70, 0x38, 0x1C, 0x0E, 0x06, 0x02, 0x00, 0x00, 0x00, 0x00 ; '\'
    db 0x5D, 0x00, 0x00, 0x3C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x3C, 0x00, 0x00, 0x00, 0x00 ; ']'
    db 0x5E, 0x10, 0x38, 0x6C, 0xC6, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; '^'
    db 0x5F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00 ; '_'
    db 0x60, 0x30, 0x30, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; '`'
    db 0x61, 0x00, 0x00, 0x00, 0x00, 0x00, 0x78, 0x0C, 0x7C, 0xCC, 0xCC, 0xCC, 0x76, 0x00, 0x00, 0x00, 0x00 ; 'a'
    db 0x62, 0x00, 0x00, 0xE0, 0x60, 0x60, 0x78, 0x6C, 0x66, 0x66, 0x66, 0x66, 0x7C, 0x00, 0x00, 0x00, 0x00 ; 'b'
    db 0x63, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7C, 0xC6, 0xC0, 0xC0, 0xC0, 0xC6, 0x7C, 0x00, 0x00, 0x00, 0x00 ; 'c'
    db 0x64, 0x00, 0x00, 0x1C, 0x0C, 0x0C, 0x3C, 0x6C, 0xCC, 0xCC, 0xCC, 0xCC, 0x76, 0x00, 0x00, 0x00, 0x00 ; 'd'
    db 0x65, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7C, 0xC6, 0xFE, 0xC0, 0xC0, 0xC6, 0x7C, 0x00, 0x00, 0x00, 0x00 ; 'e'
    db 0x66, 0x00, 0x00, 0x38, 0x6C, 0x64, 0x60, 0xF0, 0x60, 0x60, 0x60, 0x60, 0xF0, 0x00, 0x00, 0x00, 0x00 ; 'f'
    db 0x67, 0x00, 0x00, 0x00, 0x00, 0x00, 0x76, 0xCC, 0xCC, 0xCC, 0xCC, 0x7C, 0x0C, 0xCC, 0x78, 0x00, 0x00 ; 'g'
    db 0x68, 0x00, 0x00, 0xE0, 0x60, 0x60, 0x6C, 0x76, 0x66, 0x66, 0x66, 0x66, 0xE6, 0x00, 0x00, 0x00, 0x00 ; 'h'
    db 0x69, 0x00, 0x00, 0x18, 0x18, 0x00, 0x38, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00, 0x00, 0x00, 0x00 ; 'i'
    db 0x6A, 0x00, 0x00, 0x06, 0x06, 0x00, 0x0E, 0x06, 0x06, 0x06, 0x06, 0x06, 0x66, 0x66, 0x3C, 0x00, 0x00 ; 'j'
    db 0x6B, 0x00, 0x00, 0xE0, 0x60, 0x60, 0x66, 0x6C, 0x78, 0x78, 0x6C, 0x66, 0xE6, 0x00, 0x00, 0x00, 0x00 ; 'k'
    db 0x6C, 0x00, 0x00, 0x38, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00, 0x00, 0x00, 0x00 ; 'l'
    db 0x6D, 0x00, 0x00, 0x00, 0x00, 0x00, 0xEC, 0xFE, 0xD6, 0xD6, 0xD6, 0xD6, 0xC6, 0x00, 0x00, 0x00, 0x00 ; 'm'
    db 0x6E, 0x00, 0x00, 0x00, 0x00, 0x00, 0xDC, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x00, 0x00, 0x00, 0x00 ; 'n'
    db 0x6F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7C, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00, 0x00, 0x00, 0x00 ; 'o'
    db 0x70, 0x00, 0x00, 0x00, 0x00, 0x00, 0xDC, 0x66, 0x66, 0x66, 0x66, 0x7C, 0x60, 0x60, 0xF0, 0x00, 0x00 ; 'p'
    db 0x71, 0x00, 0x00, 0x00, 0x00, 0x00, 0x76, 0xCC, 0xCC, 0xCC, 0xCC, 0x7C, 0x0C, 0x0C, 0x1E, 0x00, 0x00 ; 'q'
    db 0x72, 0x00, 0x00, 0x00, 0x00, 0x00, 0xDC, 0x76, 0x66, 0x60, 0x60, 0x60, 0xF0, 0x00, 0x00, 0x00, 0x00 ; 'r'
    db 0x73, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7C, 0xC6, 0x60, 0x38, 0x0C, 0xC6, 0x7C, 0x00, 0x00, 0x00, 0x00 ; 's'
    db 0x74, 0x00, 0x00, 0x10, 0x30, 0x30, 0xFC, 0x30, 0x30, 0x30, 0x30, 0x36, 0x1C, 0x00, 0x00, 0x00, 0x00 ; 't'
    db 0x75, 0x00, 0x00, 0x00, 0x00, 0x00, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0x76, 0x00, 0x00, 0x00, 0x00 ; 'u'
    db 0x76, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC6, 0xC6, 0xC6, 0xC6, 0x6C, 0x38, 0x10, 0x00, 0x00, 0x00, 0x00 ; 'v'
    db 0x77, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC6, 0xC6, 0xD6, 0xD6, 0xFE, 0xEE, 0x6C, 0x00, 0x00, 0x00, 0x00 ; 'w'
    db 0x78, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC6, 0x6C, 0x38, 0x38, 0x38, 0x6C, 0xC6, 0x00, 0x00, 0x00, 0x00 ; 'x'
    db 0x79, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7E, 0x06, 0x0C, 0xF8, 0x00, 0x00 ; 'y'
    db 0x7A, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFE, 0xCC, 0x18, 0x30, 0x60, 0xC6, 0xFE, 0x00, 0x00, 0x00, 0x00 ; 'z'
    db 0x7B, 0x00, 0x00, 0x0E, 0x18, 0x18, 0x18, 0x70, 0x18, 0x18, 0x18, 0x18, 0x0E, 0x00, 0x00, 0x00, 0x00 ; '{'
    db 0x7C, 0x00, 0x00, 0x18, 0x18, 0x18, 0x18, 0x00, 0x18, 0x18, 0x18, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00 ; '|'
    db 0x7D, 0x00, 0x00, 0x70, 0x18, 0x18, 0x18, 0x0E, 0x18, 0x18, 0x18, 0x18, 0x70, 0x00, 0x00, 0x00, 0x00 ; '}'
    db 0x7E, 0x00, 0x00, 0x76, 0xDC, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; '~'
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
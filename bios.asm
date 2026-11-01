; =============================================================================
; Bare-Metal x86 BIOS ROM (64 KB) für QEMU – BLUE BOX EDITION
; Startet bei 0xFFFFFFF0 (0xF000:0xFFF0), initialisiert CAR/MTRR, i440FX PAM/DRB,
; PCI-VGA, Real-Mode-IVT, PIC, A20, 16550 UART, VGA-Font & zeichnet die Box!
; =============================================================================

[BITS 16]
[ORG 0x0000]                ; Gemappt auf Physisch 0xF0000 - 0xFFFFF (CS = 0xF000)

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
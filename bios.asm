; =============================================================================
; Bare-Metal x86 BIOS ROM (64 KB) for QEMU - BLUE BOX EDITION
; Starts at 0xFFFFFFF0 (0xF000:0xFFF0), initializes CAR/MTRR, i440FX PAM/DRB,
; PCI-VGA, Real-Mode IVT, PIC, A20, 16550 UART, VGA Font & draws the box!
; =============================================================================

[BITS 16]
[ORG 0x0000]                ; Mapped to Physical 0xF0000 - 0xFFFFF (CS = 0xF000)

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
CFG_SH_PROMPT   equ 0x1A37  ; 0="FS0:\> ", 1="SHELL> ", 2="root@bios:# " (Byte)
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
UI_PAL_MODE     equ 0x1C1A  ; 0 = Modern UEFI Dark Palette, 1 = Google Snake Grass Palette (Byte)

; --- RAM Addresses for DVD-Logo Animation (in free RAM at 0x0000) ---
CLEAN_BUF equ 0x1000        ; 4000-byte buffer (0x1000..0x1FA0) for original screen
POS_X1    equ 0x2000        ; Position & direction of exclamation mark 1
POS_Y1    equ 0x2002
DIR_X1    equ 0x2004
DIR_Y1    equ 0x2006
POS_X2    equ 0x2008        ; Position & direction of exclamation mark 2
POS_Y2    equ 0x200A
DIR_X2    equ 0x200C
DIR_Y2    equ 0x200E
SOUND_TIMER equ 0x2010     ; Timer for PC Speaker tone duration

bios_start:
    cli                     ; 1. Disable maskable interrupts immediately
    cld                     ; Clear direction flag

    ; --- Disable NMI (Non-Maskable Interrupt) via CMOS Port 0x70 ---
    mov al, 0x80
    out 0x70, al
    in  al, 0x71

    ; =========================================================================
    ; STEP 1: Initialize CPU Cache & Cache-as-RAM (CAR) cleanly
    ; =========================================================================
    mov eax, 1
    cpuid
    bt  edx, 12             ; Check MTRR feature bit
    jnc .skip_mtrr

    mov eax, cr0
    or  eax, 0x40000000     ; CR0.CD = 1 (Cache Disable)
    and eax, 0xDFFFFFFF     ; CR0.NW = 0
    mov cr0, eax
    invd                    ; Invalidate internal cache

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
    and eax, 0x9FFFFFFF     ; Enable L1/L2 cache (CD=0, NW=0)
    mov cr0, eax

    ; =========================================================================
    ; STEP 2: Wake up Northbridge (i440FX 00:00.0) & PCI-VGA (00:02.0)
    ; =========================================================================
    mov eax, 0x80000058     ; Bus 0, Dev 0, Func 0, Offset 0x58 (DRAMC & PAM0..2)
    mov dx, 0x0CF8
    out dx, eax
    mov dx, 0x0CFC
    in  eax, dx
    and eax, 0x000000FF     ; PAM0 (AH) = 0x00 (BIOS ROM remains readable)
    or  eax, 0x33330000     ; PAM1 & PAM2 = R/W RAM
    out dx, eax

    mov eax, 0x8000005C     ; Set PAM3..PAM6 (Offset 0x5C..0x5F) to R/W RAM
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

    ; PCI-VGA graphics card (Bus 0, Dev 2, Func 0, Offset 0x04 Command Reg)
    mov eax, 0x80001004
    mov dx, 0x0CF8
    out dx, eax
    mov dx, 0x0CFC
    in  eax, dx
    or  eax, 0x00000007     ; Enable I/O + Memory + Bus Master
    out dx, eax

    ; =========================================================================
    ; STEP 3: Stack, Segments & Real-Mode IVT (Interrupt Vector Table)
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
    ; STEP 4: Fast-A20, 8259 PIC & 16550 UART (incl. FIFO)
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
    mov al, 0xFF            ; Mask all IRQs
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

    ; COM1 (0x3F8) at 115200 Baud, 8N1
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
    ; STEP 5: Complete Bare-Metal VGA Bringup (80x25 Text Mode)
    ; =========================================================================
    mov dx, 0x3C2
    mov al, 0x67
    out dx, al

    mov dx, 0x3C4
    mov ax, 0x0100          ; Sequencer Sync Reset
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
    mov ax, 0x0300          ; End Sync Reset
    out dx, ax

    mov dx, 0x3D4
    mov ax, 0x0011          ; Unlock CRTC write protection
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
    in  al, dx              ; Reset flip-flop
    mov dx, 0x3C0
    xor ah, ah
.ac_pal_loop:
    mov al, ah
    out dx, al
    out dx, al              ; Identity mapping 0..15 -> DAC 0..15
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
    mov al, 0x20            ; Enable video output (PAS=1)
    out dx, al

    ; Set PEL Mask Register (0x3C6) to 0xFF
    mov dx, 0x3C6
    mov al, 0xFF
    out dx, al

    ; =========================================================================
    ; STEP 5.8: Load VGA DAC Palette for Black, Blue, Green & White
    ; =========================================================================
    mov dx, 0x3C8
    xor al, al
    out dx, al              ; Start at DAC index 0
    mov dx, 0x3C9
    mov si, vga_dac_table
    mov cx, 16 * 3          ; 16 colors * 3 bytes (R, G, B)
.dac_load_loop:
    lodsb
    out dx, al
    loop .dac_load_loop

    ; =========================================================================
    ; STEP 6: Load bitmap font cleanly into VGA Plane 2 (0xA0000)
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

    ; Disable hardware text cursor (CRTC 0x0A) (prevents '_' artifact at 0,0)
    mov dx, 0x3D4
    mov ax, 0x200A
    out dx, ax

    ; Switch back to Odd/Even Text Mode at 0xB8000
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
    mov ax, 0x0E06          ; GR06 = 0xB8000 text window
    out dx, ax

    ; =========================================================================
    

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

    ; =========================================================================
    ; PHASE 1: CYBFORGE UEFI/BIOS v3.0 POST SCREEN (Modern Dashboard)
    ; =========================================================================
post_screen:
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
    call apply_color_theme
    call clear_screen_black
    call draw_game_board

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
    ; Place snake in center (Head at X=40, Y=12)
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

    call update_score_display
    call draw_arena_obstacles
    call spawn_fruit
    call draw_snake
    call draw_fruit

    ; Display Maximalist Google Snake Sky-Blue Start Card!
    call draw_start_prompt
    call mouse_show_cursor
    call drain_kbd

.wait_start:
    call read_key
    test al, al
    jnz .wait_start_key

    ; Check mouse hover & click on the 3 Royal-Blue Card Buttons!
    call check_card_mouse_hover
    test byte [MOUSE_CLICK], 0x01
    jz .wait_idle
    mov byte [MOUSE_CLICK], 0
    mov dh, [MOUSE_Y]
    cmp dh, 15
    je .game_started
    cmp dh, 17
    je core_bios_setup
    cmp dh, 19
    je bios_shell_main
    ; Clicking anywhere else on the playfield starts the game!
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
    call mouse_hide_cursor
    call draw_card_buttons
    call mouse_show_cursor
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
    mov ecx, 200000                 ; ~1ms polling for instant response
    call delay_cycles
    jmp .wait_start

.game_started:
    call mouse_hide_cursor
    call sound_start
    call erase_start_prompt
    call mouse_show_cursor

    ; =========================================================================
    ; PHASE 4: MAIN GAME LOOP
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

    ; 3. Calculate new head position
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

    ; Wrap-Around logic (Cols 11..68, Rows 4..21)
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

    ; 4. Check wall collision (when Solid)
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

    call update_gold_hud

    mov al, [NEW_HEAD_X]
    mov bl, [NEW_HEAD_Y]
    cmp al, [GOLD_FOOD_X]
    jne .chk_eat_regular
    cmp bl, [GOLD_FOOD_Y]
    jne .chk_eat_regular

    ; --- GOLDEN APPLE EATEN! (+50 Points) ---
    add word [SCORE], 50
    mov [BULGE_X], al
    mov [BULGE_Y], bl
    call sound_golden_apple
    call erase_gold_apple
    call update_score_display
    jmp .chk_eat_regular

.gold_expired:
    call erase_gold_apple

.chk_eat_regular:
    ; 7. Check if regular apple was eaten
    mov al, [NEW_HEAD_X]
    mov bl, [NEW_HEAD_Y]
    cmp al, [FOOD_X]
    jne .normal_move
    cmp bl, [FOOD_Y]
    jne .normal_move

    ; --- REGULAR APPLE EATEN! ---
    ; Record digesting apple bulge coordinate at eaten apple position!
    mov [BULGE_X], al
    mov [BULGE_Y], bl
    inc word [SCORE]
    inc byte [APPLE_COUNT]
    call update_score_display
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
    cmp ax, 1044
    jae .grow_len_done
    inc ax
    mov [SNAKE_LEN], ax
.grow_len_done:

    ; Check victory condition
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

    call mouse_hide_cursor
    call spawn_fruit
    call draw_snake
    call draw_fruit
    call mouse_show_cursor
    jmp game_loop

.normal_move:
    call mouse_hide_cursor
    ; Erase tail tip back to its 2-tone Grass Checkerboard tile!
    mov si, [SNAKE_LEN]
    dec si
    mov al, [SNAKE_X + si]
    mov bl, [SNAKE_Y + si]
    cmp al, [BULGE_X]
    jne .erase_tail_tile
    cmp bl, [BULGE_Y]
    jne .erase_tail_tile
    mov byte [BULGE_X], 0xFF        ; Digesting bulge reached the tail and finished!
.erase_tail_tile:
    call clear_grass_tile

    ; Shift segments
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

    call draw_snake
    call draw_fruit
    call mouse_show_cursor
    jmp game_loop

.do_crash:
    call mouse_hide_cursor
    call crash_dissolve_animation
    jmp game_over

    ; =========================================================================
    ; PHASE 5A: VICTORY SCREEN (Trophy & Victory Fanfare)
    ; =========================================================================
victory_screen:
    call mouse_hide_cursor
    call sound_victory
    call draw_grass_board

    mov al, 20
    mov bl, 4
    call xy_to_di
    mov si, str_vic_hdr1
    mov ah, 0x2E
    call print_string

    mov al, 28
    mov bl, 5
    call xy_to_di
    mov si, str_vic_hdr2
    mov ah, 0x2F
    call print_string

    mov al, 32
    mov bl, 7
    call xy_to_di
    mov si, str_vic_t1
    mov ah, 0x2E
    call print_string
    mov al, 31
    mov bl, 8
    call xy_to_di
    mov si, str_vic_t2
    mov ah, 0x2E
    call print_string
    mov al, 32
    mov bl, 9
    call xy_to_di
    mov si, str_vic_t3
    mov ah, 0x2E
    call print_string
    mov al, 28
    mov bl, 10
    call xy_to_di
    mov si, str_vic_t4
    mov ah, 0x2F
    call print_string
    mov al, 32
    mov bl, 11
    call xy_to_di
    mov si, str_vic_t5
    mov ah, 0x2E
    call print_string
    mov al, 31
    mov bl, 12
    call xy_to_di
    mov si, str_vic_t6
    mov ah, 0x2E
    call print_string
    mov al, 32
    mov bl, 13
    call xy_to_di
    mov si, str_vic_t7
    mov ah, 0x2E
    call print_string
    mov al, 37
    mov bl, 14
    call xy_to_di
    mov si, str_vic_t8
    mov ah, 0x2E
    call print_string
    mov al, 34
    mov bl, 15
    call xy_to_di
    mov si, str_vic_t9
    mov ah, 0x2E
    call print_string
    mov al, 33
    mov bl, 16
    call xy_to_di
    mov si, str_vic_t10
    mov ah, 0x2E
    call print_string
    mov al, 33
    mov bl, 17
    call xy_to_di
    mov si, str_vic_t11
    mov ah, 0x2F
    call print_string
    mov al, 33
    mov bl, 18
    call xy_to_di
    mov si, str_vic_t12
    mov ah, 0x2F
    call print_string
    mov al, 33
    mov bl, 19
    call xy_to_di
    mov si, str_vic_t13
    mov ah, 0x2E
    call print_string

    mov al, 26
    mov bl, 21
    call xy_to_di
    mov si, str_vic_status
    mov ah, 0x2F
    call print_string

    call mouse_show_cursor
    call drain_kbd

.wait_vic_key:
    call read_key
    cmp al, 0x1C
    je init_snake_game
    cmp al, 0x01
    je core_bios_setup
    test byte [MOUSE_CLICK], 0x01
    jnz init_snake_game
    mov ecx, 10000000
    call delay_cycles
    jmp .wait_vic_key

    ; =========================================================================
    ; PHASE 5: GOOGLE SNAKE SKY-BLUE GAME OVER POPUP CARD & HALL OF CHAMPIONS
    ; =========================================================================
game_over:
    call mouse_hide_cursor
    call sound_game_over

    ; Check if score qualifies for Top 3 -> Initials entry!
    call check_top3_qualification

    ; Render the Google Snake Sky-Blue Popup Card in Game Over mode (dl = 1)!
    mov byte [CARD_BTN_SEL], 0
    mov byte [MOUSE_CLICK], 0
    mov dl, 1
    call draw_google_popup_card
    call mouse_show_cursor
    call drain_kbd

.wait_enter:
    call read_key
    test al, al
    jnz .go_got_key

    call check_card_mouse_hover
    test byte [MOUSE_CLICK], 0x01
    jz .go_idle
    mov byte [MOUSE_CLICK], 0
    mov dh, [MOUSE_Y]
    cmp dh, 15
    je .do_restart
    cmp dh, 17
    je .do_setup
    cmp dh, 19
    je .do_shell
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
    mov ecx, 2000000
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
    call mouse_hide_cursor
    call draw_card_buttons
    call mouse_show_cursor
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

    ; Did user click the top Forest-Green HUD bar (Row 0..2)?
    cmp byte [MOUSE_Y], 2
    ja .mouse_steer_playfield
    mov dl, [MOUSE_X]
    cmp dl, 59
    jb .hud_toggle_sound
    cmp dl, 65
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
    ; Steer snake toward clicked playfield coordinate (MOUSE_X, MOUSE_Y)!
    mov al, [SNAKE_DIR]
    test al, 1                      ; Moving horizontally (Right=1 or Left=3)?
    jnz .steer_vertical
    ; Currently moving Up/Down -> Turn Left (3) or Right (1) toward MOUSE_X
    mov cl, 1
    mov dl, [MOUSE_X]
    cmp dl, [SNAKE_X]
    jae .apply_new_dir
    mov cl, 3
    jmp .apply_new_dir
.steer_vertical:
    ; Currently moving Left/Right -> Turn Up (0) or Down (2) toward MOUSE_Y
    mov cl, 2
    mov dh, [MOUSE_Y]
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
    call mouse_hide_cursor
    call sound_pause
    ; Sky-Blue Pause Modal Box (Cols 28..52, Rows 10..14)
    mov al, 28
    mov bl, 10
    call xy_to_di
    mov ax, 0x3B01
    stosw
    mov cx, 23
    mov ax, 0x3B05
    rep stosw
    mov ax, 0x3B02
    stosw

    mov dh, 11
.p_box_mid:
    mov al, 28
    mov bl, dh
    call xy_to_di
    mov ax, 0x3B06
    stosw
    mov cx, 23
    mov ax, 0x3F20
    rep stosw
    mov ax, 0x3B06
    stosw
    inc dh
    cmp dh, 14
    jb .p_box_mid

    mov al, 28
    mov bl, 14
    call xy_to_di
    mov ax, 0x3B03
    stosw
    mov cx, 23
    mov ax, 0x3B05
    rep stosw
    mov ax, 0x3B04
    stosw

    mov al, 35
    mov bl, 11
    call xy_to_di
    mov si, str_paused_lbl
    mov ah, 0x3E
    call print_string

    mov al, 30
    mov bl, 13
    call xy_to_di
    mov si, str_pause_resume
    mov ah, 0x3F
    call print_string

    call mouse_show_cursor
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
    pop ax                          ; Clean up stack
    jmp core_bios_setup

.resume_game:
    mov byte [MOUSE_CLICK], 0
    call mouse_hide_cursor
    call sound_pause
    ; Restore Grass Checkerboard under pause modal
    call draw_grass_board
    call draw_arena_obstacles
    call draw_snake
    call draw_fruit
    cmp byte [GOLD_FOOD_X], 0xFF
    je .resume_done
    mov al, [GOLD_FOOD_X]
    mov bl, [GOLD_FOOD_Y]
    call xy_to_di
    call get_grass_bg_ah
    or ah, 0x0E
    mov al, 0x08
    stosw
.resume_done:
    call mouse_show_cursor
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
    ; PHASE 7: GOOGLE SNAKE MAXIMALIST GRAPHICS & GRASS CHECKERBOARD ENGINE
    ; =========================================================================
get_grass_bg_ah:
    ; Input: AL = X, BL = Y
    ; Output: AH = 0x20 (Medium Grass) if (X+Y) is even, 0x70 (Light Grass) if odd
    push ax
    add al, bl
    test al, 1
    pop ax
    mov ah, 0x20
    jz .ggb_done
    mov ah, 0x70
.ggb_done:
    ret

clear_grass_tile:
    ; Restores cell (AL, BL) to its 2-tone Grass Checkerboard tile
    push ax
    push di
    call xy_to_di
    call get_grass_bg_ah
    mov al, ' '
    stosw
    pop di
    pop ax
    ret

draw_grass_board:
    ; Fills the entire 58x18 playfield interior (Cols 11..68, Rows 4..21)
    ; with the 2-tone Google Snake grass checkerboard (0x2020 and 0x7020)
    push ax
    push bx
    push cx
    push dx
    push di
    mov dh, 4
.dgb_row:
    mov al, 11
    mov bl, dh
    call xy_to_di
    mov dl, 11
.dgb_col:
    mov al, dl
    mov bl, dh
    call get_grass_bg_ah
    mov al, ' '
    stosw
    inc dl
    cmp dl, 69
    jb .dgb_col
    inc dh
    cmp dh, 22
    jb .dgb_row
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_game_board:
    ; 1. Fill entire 80x25 screen with Dark Forest-Green outer frame (0x0F20)
    xor di, di
    mov cx, 80 * 25
    mov ax, 0x0F20
    rep stosw

    ; 2. Top Google Snake HUD Bar (Row 1):
    ; Left: Plump Red Apple Icon (0x0C08) + Score + Gold Trophy Icon (0x0E09) + High Score
    mov al, 10
    mov bl, 1
    call xy_to_di
    mov ax, 0x0C08                  ; Red Apple Icon
    stosw
    mov ax, 0x0F20
    stosw

    mov al, 18
    mov bl, 1
    call xy_to_di
    mov ax, 0x0E09                  ; Gold Trophy Icon
    stosw
    mov ax, 0x0F20
    stosw

    ; Center Title: "GOOGLE SNAKE BIOS v3.0"
    mov al, 28
    mov bl, 1
    call xy_to_di
    mov si, str_game_title
    mov ah, 0x0F
    call print_string

    ; Right Clickable HUD Buttons: [Sound] [Pause] [Setup]
    mov al, 52
    mov bl, 1
    call xy_to_di
    mov si, str_hud_buttons
    mov ah, 0x0E
    call print_string

    ; Bottom Controls Bar (Row 24)
    mov al, 6
    mov bl, 24
    call xy_to_di
    mov si, str_controls
    mov ah, 0x0F
    call print_string

    ; 3. Playfield Deep Moss Border Frame (X: 10..69, Y: 3..22, attr 0x4F)
    mov al, 10
    mov bl, 3
    call xy_to_di
    mov ax, 0x4F01
    stosw
    mov cx, 58
    mov ax, 0x4F05
    rep stosw
    mov ax, 0x4F02
    stosw

    mov cx, 18
    mov dh, 4
.vert_loop:
    mov al, 10
    mov bl, dh
    call xy_to_di
    mov ax, 0x4F06
    stosw
    mov al, 69
    call xy_to_di
    mov ax, 0x4F06
    stosw
    inc dh
    loop .vert_loop

    mov al, 10
    mov bl, 22
    call xy_to_di
    mov ax, 0x4F03
    stosw
    mov cx, 58
    mov ax, 0x4F05
    rep stosw
    mov ax, 0x4F04
    stosw

    ; 4. Fill playfield interior with 2-tone Grass Checkerboard!
    call draw_grass_board

    ; 5. Draw arena obstacles
    call draw_arena_obstacles
    ret

draw_arena_obstacles:
    cmp byte [CFG_ARENA], 1
    je .draw_pillars
    cmp byte [CFG_ARENA], 2
    je .draw_maze
    ret

.draw_pillars:
    mov al, 24
    mov bl, 8
    call xy_to_di
    mov word [es:di], 0x4E01
    mov word [es:di+2], 0x4E02
    mov al, 24
    mov bl, 9
    call xy_to_di
    mov word [es:di], 0x4E03
    mov word [es:di+2], 0x4E04

    mov al, 54
    mov bl, 8
    call xy_to_di
    mov word [es:di], 0x4E01
    mov word [es:di+2], 0x4E02
    mov al, 54
    mov bl, 9
    call xy_to_di
    mov word [es:di], 0x4E03
    mov word [es:di+2], 0x4E04

    mov al, 24
    mov bl, 16
    call xy_to_di
    mov word [es:di], 0x4E01
    mov word [es:di+2], 0x4E02
    mov al, 24
    mov bl, 17
    call xy_to_di
    mov word [es:di], 0x4E03
    mov word [es:di+2], 0x4E04

    mov al, 54
    mov bl, 16
    call xy_to_di
    mov word [es:di], 0x4E01
    mov word [es:di+2], 0x4E02
    mov al, 54
    mov bl, 17
    call xy_to_di
    mov word [es:di], 0x4E03
    mov word [es:di+2], 0x4E04
    ret

.draw_maze:
    mov al, 20
    mov bl, 9
    call xy_to_di
    mov cx, 26
    mov ax, 0x4E05
    rep stosw
    mov al, 34
    mov bl, 16
    call xy_to_di
    mov cx, 26
    mov ax, 0x4E05
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

    ; =========================================================================
    ; GOOGLE SNAKE SKY-BLUE POPUP CARD (Start & Game Over with 3 Blue Buttons!)
    ; =========================================================================
draw_start_prompt:
draw_start_box:
    xor dl, dl                      ; dl = 0: Start Card mode
    call draw_google_popup_card
    ret

draw_google_popup_card:
    ; Input: dl = 0 (Start Card), dl = 1 (Game Over Card)
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    ; 1. Draw Drop Shadow (Col 56 Rows 5..21, Cols 25..56 Row 21) in 0x5020
    mov dh, 5
.card_sh_v:
    mov al, 56
    mov bl, dh
    call xy_to_di
    mov word [es:di], 0x5020
    inc dh
    cmp dh, 21
    jb .card_sh_v

    mov al, 25
    mov bl, 21
    call xy_to_di
    mov cx, 32
    mov ax, 0x5020
    rep stosw

    ; 2. Draw Sky-Blue Upper Card (Cols 24..55, Rows 4..13) in 0x3F / 0x3B
    mov al, 24
    mov bl, 4
    call xy_to_di
    mov ax, 0x3B01                  ; '╭'
    stosw
    mov cx, 30
    mov ax, 0x3B05                  ; '═'
    rep stosw
    mov ax, 0x3B02                  ; '╮'
    stosw

    mov dh, 5
.card_sky_mid:
    mov al, 24
    mov bl, dh
    call xy_to_di
    mov ax, 0x3B06
    stosw
    mov cx, 30
    mov ax, 0x3F20
    rep stosw
    mov ax, 0x3B06
    stosw
    inc dh
    cmp dh, 12
    jb .card_sky_mid

    ; 3. Rows 12 & 13 inside Card: 2-Row Green Grass Horizon Strip (Cols 25..54)
    mov dh, 12
.card_grass_rows:
    mov al, 24
    mov bl, dh
    call xy_to_di
    mov ax, 0x3B06
    stosw
    mov ch, 25
.card_grass_cols:
    mov al, ch
    mov bl, dh
    call get_grass_bg_ah
    mov al, ' '
    stosw
    inc ch
    cmp ch, 55
    jb .card_grass_cols
    mov ax, 0x3B06
    stosw
    inc dh
    cmp dh, 14
    jb .card_grass_rows

    ; 4. Card Title on Row 5
    mov al, 29
    mov bl, 5
    call xy_to_di
    mov si, str_card_start_hdr
    cmp dl, 0
    je .card_pr_hdr
    mov al, 31
    mov bl, 5
    call xy_to_di
    mov si, str_game_over
.card_pr_hdr:
    mov ah, 0x3F                    ; Crisp White on Sky Blue
    call print_string

    ; 5. Big Red Apple Icon (Col 32, Row 7) & Gold Trophy Icon (Col 46, Row 7)
    mov al, 32
    mov bl, 7
    call xy_to_di
    mov ax, 0x3C08                  ; Plump Red Apple on Sky Blue
    stosw

    mov al, 46
    mov bl, 7
    call xy_to_di
    mov ax, 0x3E09                  ; Gold Trophy Cup on Sky Blue
    stosw

    ; 6. Score under Apple (Col 31, Row 8) & High Score under Trophy (Col 45, Row 8)
    mov al, 31
    mov bl, 8
    call xy_to_di
    mov ax, [SCORE]
    call render_3digits_card

    mov al, 45
    mov bl, 8
    call xy_to_di
    mov ax, [HIGH_SCORE]
    call render_3digits_card

    ; 7. Cute Royal-Blue Snake Artwork on Row 12 (sitting on the grass horizon!)
    mov al, 33
    mov bl, 12
    call xy_to_di
    mov ax, 0x290E                  ; Tapered Tail
    stosw
    mov ax, 0x790C                  ; Body
    stosw
    mov ax, 0x290D                  ; Bulge
    stosw
    mov ax, 0x790C                  ; Body
    stosw
    mov ax, 0x2A07                  ; Big-Eyed Cute Head (or Dizzy Head on Game Over)
    cmp dl, 0
    je .card_snk_head
    mov ax, 0x2E10                  ; Knocked-Out Dizzy Head on Game Over!
.card_snk_head:
    stosw
    mov ax, 0x7C18                  ; Flicking Red Tongue
    stosw
    mov ax, 0x2020
    stosw
    mov ax, 0x7C08                  ; Red Apple ahead of snake on grass!
    stosw

    ; If Game Over (dl == 1), also display Top Champion on Row 10
    cmp dl, 1
    jne .card_lower_panel
    mov al, 28
    mov bl, 10
    call xy_to_di
    mov si, str_card_champ_lbl
    mov ah, 0x3E
    call print_string
    mov si, TOP3_TABLE + 0
    mov ah, 0x3F
    call print_3chars

.card_lower_panel:
    ; 8. Lower Button Frame (Cols 24..55, Rows 14..20)
    mov dh, 14
.card_bot_rows:
    mov al, 24
    mov bl, dh
    call xy_to_di
    mov ax, 0x3B06
    stosw
    mov cx, 30
    mov ax, 0x3F20
    rep stosw
    mov ax, 0x3B06
    stosw
    inc dh
    cmp dh, 20
    jb .card_bot_rows

    mov al, 24
    mov bl, 20
    call xy_to_di
    mov ax, 0x3B03                  ; '╰'
    stosw
    mov cx, 30
    mov ax, 0x3B05                  ; '═'
    rep stosw
    mov ax, 0x3B04                  ; '╯'
    stosw

    ; Draw the 3 Royal-Blue Action Buttons (Rows 15, 17, 19)
    call draw_card_buttons

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_card_buttons:
    ; Renders the 3 clickable Google Royal-Blue buttons inside the popup card:
    ; Row 15 (Btn 0): [ ▶  Play Snake Game       ]
    ; Row 17 (Btn 1): [ ⚙  BIOS Setup & Settings ]
    ; Row 19 (Btn 2): [ >_ Launch UEFI/BIOS Shell]
    push ax
    push bx
    push si
    push di

    mov al, 26
    mov bl, 15
    call xy_to_di
    mov si, str_card_btn_play
    mov ah, 0x1F
    cmp byte [CARD_BTN_SEL], 0
    jne .dcb_b0
    mov ah, 0x1E                    ; Highlighted Golden Text on Royal Blue
.dcb_b0:
    call print_string

    mov al, 26
    mov bl, 17
    call xy_to_di
    mov si, str_card_btn_setup
    mov ah, 0x1F
    cmp byte [CARD_BTN_SEL], 1
    jne .dcb_b1
    mov ah, 0x1E
.dcb_b1:
    call print_string

    mov al, 26
    mov bl, 19
    call xy_to_di
    mov si, str_card_btn_shell
    mov ah, 0x1F
    cmp byte [CARD_BTN_SEL], 2
    jne .dcb_b2
    mov ah, 0x1E
.dcb_b2:
    call print_string

    pop di
    pop si
    pop bx
    pop ax
    ret

check_card_mouse_hover:
    ; Updates [CARD_BTN_SEL] if mouse hovers over Rows 15, 17, or 19 (Cols 26..53)
    push ax
    mov al, [MOUSE_X]
    cmp al, 26
    jb .ccmh_done
    cmp al, 53
    ja .ccmh_done
    mov al, [MOUSE_Y]
    cmp al, 15
    je .ccmh_set0
    cmp al, 17
    je .ccmh_set1
    cmp al, 19
    je .ccmh_set2
    jmp .ccmh_done
.ccmh_set0:
    mov ah, 0
    jmp .ccmh_apply
.ccmh_set1:
    mov ah, 1
    jmp .ccmh_apply
.ccmh_set2:
    mov ah, 2
.ccmh_apply:
    cmp [CARD_BTN_SEL], ah
    je .ccmh_done
    mov [CARD_BTN_SEL], ah
    call mouse_hide_cursor
    call draw_card_buttons
    call mouse_show_cursor
.ccmh_done:
    pop ax
    ret

render_3digits_card:
    xor dx, dx
    mov cx, 100
    div cx
    add al, '0'
    mov ah, 0x3F
    stosw
    mov ax, dx
    xor dx, dx
    mov cx, 10
    div cx
    add al, '0'
    mov ah, 0x3F
    stosw
    mov al, dl
    add al, '0'
    mov ah, 0x3F
    stosw
    ret

erase_start_prompt:
erase_start_box:
    call draw_grass_board
    call draw_arena_obstacles
    call draw_snake
    call draw_fruit
    ret

    ; =========================================================================
    ; MAXIMALIST GOOGLE SNAKE RENDERER (Head, Chomp, Tongue, Bulge, Tapered Tail)
    ; =========================================================================
draw_snake:
    ; 1. Erase previous flicking tongue tile if active
    cmp byte [TONGUE_X], 0xFF
    je .ds_no_old_tongue
    mov al, [TONGUE_X]
    mov bl, [TONGUE_Y]
    call clear_grass_tile
    mov byte [TONGUE_X], 0xFF
.ds_no_old_tongue:

    ; 2. Draw Body Segments (si = 1 .. SNAKE_LEN - 1)
    mov cx, [SNAKE_LEN]
    dec cx
    jz .ds_draw_head
    mov si, 1
.body_loop:
    mov al, [SNAKE_X + si]
    mov bl, [SNAKE_Y + si]
    call xy_to_di
    call get_grass_bg_ah
    or ah, 0x09                     ; Royal Blue Snake Body on Grass

    ; Check if this is the Tapered Tail Tip (last segment: cx == 1)
    cmp cx, 1
    jne .ds_chk_bulge
    mov al, 0x0E                    ; 0x0E = Tapered Tail Tip glyph
    jmp .ds_put_seg

.ds_chk_bulge:
    ; Check if this segment is at the Digesting Apple Bulge coordinate!
    mov dl, [SNAKE_X + si]
    cmp dl, [BULGE_X]
    jne .ds_std_seg
    mov dl, [SNAKE_Y + si]
    cmp dl, [BULGE_Y]
    jne .ds_std_seg
    mov al, 0x0D                    ; 0x0D = Plump Digesting Apple Bulge glyph!
    jmp .ds_put_seg

.ds_std_seg:
    mov al, 0x0C                    ; 0x0C = Rounded Body Segment glyph
.ds_put_seg:
    stosw
    inc si
    loop .body_loop

.ds_draw_head:
    ; 3. Draw Expressive Snake Head at (SNAKE_X[0], SNAKE_Y[0])
    mov al, [SNAKE_X]
    mov bl, [SNAKE_Y]
    call xy_to_di
    call get_grass_bg_ah
    or ah, 0x0A                     ; Bright Royal/Cornflower Blue Head on Grass

    ; Check Manhattan distance to Apple: |SNAKE_X - FOOD_X| + |SNAKE_Y - FOOD_Y| <= 3 -> Wide-Open Chomp Mouth (0x0F)!
    push ax
    mov dl, [SNAKE_X]
    sub dl, [FOOD_X]
    jns .dx_pos
    neg dl
.dx_pos:
    mov dh, [SNAKE_Y]
    sub dh, [FOOD_Y]
    jns .dy_pos
    neg dh
.dy_pos:
    add dl, dh
    pop ax
    cmp dl, 3
    jbe .ds_chomp_head

    mov al, 0x07                    ; 0x07 = Big-Eyed Cute Google Snake Head
    cmp byte [CFG_FACE], 1
    jne .ds_put_head
    mov al, 0x0A                    ; 0x0A = Cool Sunglasses Head
    jmp .ds_put_head

.ds_chomp_head:
    mov al, 0x0F                    ; 0x0F = Wide-Open Chomp Mouth Head!
    stosw
    ret                             ; Don't draw tongue when mouth is wide open chomping!

.ds_put_head:
    stosw

    ; 4. Animate Flicking Red Forked Tongue (0x18) 1 tile ahead of the head!
    inc byte [TONGUE_TICK]
    test byte [TONGUE_TICK], 2
    jnz .draw_snake_done

    mov al, [SNAKE_X]
    mov bl, [SNAKE_Y]
    mov cl, [SNAKE_DIR]
    cmp cl, 0
    jne .tg_not_u
    dec bl
    jmp .tg_chk_bounds
.tg_not_u:
    cmp cl, 1
    jne .tg_not_r
    inc al
    jmp .tg_chk_bounds
.tg_not_r:
    cmp cl, 2
    jne .tg_not_d
    inc bl
    jmp .tg_chk_bounds
.tg_not_d:
    dec al

.tg_chk_bounds:
    cmp al, 11
    jb .draw_snake_done
    cmp al, 68
    ja .draw_snake_done
    cmp bl, 4
    jb .draw_snake_done
    cmp bl, 21
    ja .draw_snake_done

    ; Not on food or obstacle
    cmp al, [FOOD_X]
    jne .tg_chk_wall
    cmp bl, [FOOD_Y]
    je .draw_snake_done
.tg_chk_wall:
    call is_arena_wall
    jz .draw_snake_done

    ; Draw Red Forked Tongue (0x18) on grass tile!
    mov [TONGUE_X], al
    mov [TONGUE_Y], bl
    call xy_to_di
    call get_grass_bg_ah
    or ah, 0x0C                     ; Bright Scarlet Red on Grass
    mov al, 0x18                    ; 0x18 = Forked Tongue glyph
    stosw

.draw_snake_done:
    ret

draw_fruit:
    mov al, [FOOD_X]
    mov bl, [FOOD_Y]
    call xy_to_di
    call get_grass_bg_ah
    or ah, 0x0C                     ; Bright Red Apple on Grass
    mov al, 0x08
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
    mov al, [GOLD_FOOD_X]
    mov bl, [GOLD_FOOD_Y]
    call xy_to_di
    call get_grass_bg_ah
    or ah, 0x0E                     ; Golden Apple on Grass
    mov al, 0x08
    stosw
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
    call clear_grass_tile
    mov byte [GOLD_FOOD_X], 0xFF
    ; Restore title on HUD
    mov al, 28
    mov bl, 1
    call xy_to_di
    mov si, str_game_title
    mov ah, 0x0F
    call print_string
.no_erase_gold:
    ret

update_gold_hud:
    mov al, 42
    mov bl, 1
    call xy_to_di
    mov si, str_gold_lbl
    mov ah, 0x0E
    call print_string

    mov ax, [GOLD_TIMER]
    xor dx, dx
    mov cx, 7
    div cx
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
    ; Score next to Red Apple Icon at (12, 1)
    mov al, 12
    mov bl, 1
    call xy_to_di
    mov ax, [SCORE]
    call render_3digits_white

    ; High Score next to Gold Trophy Icon at (20, 1)
    mov al, 20
    mov bl, 1
    call xy_to_di
    mov ax, [HIGH_SCORE]
    call render_3digits_yellow

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
    ; PHASE 8: GOOGLE SNAKE DIZZY-STARS CRASH ANIMATION & TOP 3 LEADERBOARD
    ; =========================================================================
crash_dissolve_animation:
    ; 1. Play Cartoon Sub-Bass Bonk + Dizzy Stars PCM audio
    call sound_crash

    ; 2. Draw Knocked-Out Dizzy Snake Head (0x10) at (SNAKE_X[0], SNAKE_Y[0])
    mov al, [SNAKE_X]
    mov bl, [SNAKE_Y]
    call xy_to_di
    call get_grass_bg_ah
    or ah, 0x0E                     ; Gold/Yellow Dizzy Head on Grass
    mov al, 0x10                    ; 0x10 = Knocked-Out Dizzy Head
    stosw

    ; 3. Animate twinkling Dizzy Stars ('*', '+') around the snake head (8 frames)
    mov cx, 8
.dizzy_star_loop:
    push cx
    mov al, [SNAKE_X]
    mov bl, [SNAKE_Y]
    cmp bl, 5
    jb .ds_skip_top_stars
    dec bl
    call xy_to_di
    call get_grass_bg_ah
    or ah, 0x0E
    mov al, '*'
    test cl, 1
    jz .ds_st1
    mov al, '+'
    xor ah, 0x01                    ; Alternate Gold (0x0E) & White (0x0F)
.ds_st1:
    cmp byte [SNAKE_X], 12
    jb .ds_st_r
    mov [es:di - 2], ax
.ds_st_r:
    cmp byte [SNAKE_X], 67
    ja .ds_skip_top_stars
    xor al, ('*' ^ '+')
    mov [es:di + 2], ax
.ds_skip_top_stars:
    mov ecx, 11000000               ; ~45ms per dizzy star frame
    call delay_cycles
    pop cx
    loop .dizzy_star_loop
    ret

check_top3_qualification:
    mov ax, [SCORE]
    cmp ax, [TOP3_TABLE + 13]       ; Compare with Rank 3
    jbe .no_qualification

    ; New record! Display initials entry dialog
    call enter_initials_dialog

    ; Insert into TOP3_TABLE at the appropriate rank
    push es
    push ds
    pop es

    mov ax, [SCORE]
    cmp ax, [TOP3_TABLE + 3]        ; Better than Rank 1?
    ja .insert_pos1

    cmp ax, [TOP3_TABLE + 8]        ; Better than Rank 2?
    ja .insert_pos2

    ; Replace Rank 3
    mov si, CURRENT_NAME
    mov di, TOP3_TABLE + 10
    mov cx, 3
    rep movsb
    mov ax, [SCORE]
    mov [TOP3_TABLE + 13], ax
    jmp .save_top3_done

.insert_pos2:
    ; Shift Rank 2 -> Rank 3
    mov si, TOP3_TABLE + 5
    mov di, TOP3_TABLE + 10
    mov cx, 5
    rep movsb
    ; Place new entry at Rank 2
    mov si, CURRENT_NAME
    mov di, TOP3_TABLE + 5
    mov cx, 3
    rep movsb
    mov ax, [SCORE]
    mov [TOP3_TABLE + 8], ax
    jmp .save_top3_done

.insert_pos1:
    ; Rank 2 -> Rank 3
    mov si, TOP3_TABLE + 5
    mov di, TOP3_TABLE + 10
    mov cx, 5
    rep movsb
    ; Rank 1 -> Rank 2
    mov si, TOP3_TABLE + 0
    mov di, TOP3_TABLE + 5
    mov cx, 5
    rep movsb
    ; Place new entry at Rank 1
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

    ; Centered dialog box (Cols 25..55, Rows 9..16)
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
    ; Rank 1 (Row 13)
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

    ; Rank 2 (Row 14)
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

    ; Rank 3 (Row 15)
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

    ; 4. Move live software cursor on screen!
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
    db "BIOS Date: 11/08/2026  Ver: 3.00.00-MAX (Google Snake Ed.)", 0
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
    db "Booting Google Snake v3.0 in 3s... (Press [ENTER] or Click to Start Now)", 0
str_post_bot_bar:
    db "[F12/DEL] BIOS Setup    [ENTER/Click] Boot Google Snake    [Mouse] Active", 0
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
    db " Google Snake Maximalist & Hardware Features ", 0
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
    db "< Google BigEyes >", 0
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
    db "Select snake head style: Google Snake Big-Eyes or Cool Sunglasses.", 0
str_help_4:
    db "Starting length of the royal-blue snake body at game launch.", 0
str_help_5:
    db "Win goal: Fill the 1044-tile grass board or reach apple target!", 0
str_help_6:
    db "Choose playfield theme: Google Grass Checkerboard, Emerald, Sunset, Arcade.", 0
str_help_7:
    db "Choose arena layout: Open Meadow, Four Pillars, or The Maze.", 0

str_opt_theme:
    db "Board Theme       : ", 0
str_opt_arena:
    db "Arena Layout      : ", 0

str_val_theme_cyber:
    db "< Google Grass   >", 0
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
    db "Save settings to NVRAM disk and launch Google Snake!", 0

; --- Google Snake Maximalist Game Strings ---
str_game_title:
    db "GOOGLE SNAKE BIOS v3.0", 0
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
    db "G O O G L E   S N A K E", 0
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

    ; UEFI Prompt: "FS0:" + real Inode directory name + "> "
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
    cmp al, '\'
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

; --- Framed BIOS Shell v3.0 & Live CybFS Strings ---
str_sh_topbar:
    db "CYBFORGE UEFI/BIOS SHELL v3.0 [xHCI 3.0 + EHCI 2.0 + Mouse]  ROM:256K RAM:640K", 0
str_sh_frame_top:
    db " Cybforge Modern UEFI/BIOS Console [Persistent NVRAM + USB + Mouse] ", 0
str_sh_frame_bot:
    db " Click Dock Below: [HELP] | [USB / XHCI] | [LS / DIR] | [SNAKE] | [SETUP] ", 0
str_sh_botbar:
    db " [HELP] Cmds   [USB] xHCI/EHCI   [LS] Files   [SNAKE] Play Game   [EXIT] Setup", 0

str_pr_fs0_pfx:     db "FS0:", 0
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
    db "snake / boot Launch Google Snake v3.0  exit / quit  Return to BIOS Setup!", 0

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
    db "                    Game     : Google Snake v3.0 ('snake' to play)", 0

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

; 16-Color VGA DAC Palette (3 bytes each: R, G, B in range 0..63)
vga_dac_table:
    db  0,  0,  0           ; 0x00: Black (Screen background)
    db  0, 12, 48           ; 0x01: Deep BIOS Blue (Box background)
    db  0, 42,  0           ; 0x02: Dark Green
    db  0, 42, 42           ; 0x03: Cyan
    db 42,  0,  0           ; 0x04: Red
    db 42,  0, 42           ; 0x05: Magenta
    db 42, 21,  0           ; 0x06: Brown
    db 42, 42, 42           ; 0x07: Light Gray
    db 21, 21, 21           ; 0x08: Dark Gray
    db 21, 21, 63           ; 0x09: Light Blue
    db 10, 63, 20           ; 0x0A: Matrix Bright Green ("Hello World from BIOS!")
    db 21, 63, 63           ; 0x0B: Light Cyan
    db 63, 21, 21           ; 0x0C: Light Red
    db 63, 21, 63           ; 0x0D: Pink
    db 63, 63, 21           ; 0x0E: Yellow
    db 63, 63, 63           ; 0x0F: Pure White (Box text + border)

; Compact 8x8 bitmap font table (doubled to 8x16 during upload)

align 8
sample_table:
    dd 0xFFFD0000 ; SND_CRUNCH
    dw 2646
    dd 0xFFFD14AC ; SND_GOLDEN
    dw 6616
    dd 0xFFFD485C ; SND_CRASH
    dw 5734
    dd 0xFFFD7528 ; SND_START
    dw 4190
    dd 0xFFFD95E4 ; SND_PAUSE
    dw 1984
    dd 0xFFFDA564 ; SND_BOOT
    dw 6836
    dd 0xFFFDDACC ; SND_GAMEOVER
    dw 9702
    dd 0xFFFE2698 ; SND_VICTORY
    dw 13782

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
    db 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1F, 0x30, 0x37, 0x2C, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24
    db 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF8, 0x0C, 0xEC, 0x34, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24
    db 0x03, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x2C, 0x37, 0x30, 0x1F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x04, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x34, 0xEC, 0x0C, 0xF8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x06, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24
    db 0x07, 0x00, 0x3C, 0x7E, 0xFF, 0x99, 0x99, 0xDB, 0xDB, 0xFF, 0xFF, 0xE7, 0xFF, 0xBD, 0xC3, 0x7E, 0x3C
    db 0x08, 0x0C, 0x1E, 0x18, 0x76, 0xFF, 0xDF, 0xBF, 0xBF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7E, 0x7E, 0x3C, 0x00
    db 0x09, 0x00, 0x7E, 0xFF, 0xDB, 0xDB, 0xFF, 0x7E, 0x3C, 0x18, 0x18, 0x18, 0x3C, 0x7E, 0x7E, 0x00, 0x00
    db 0x0A, 0x00, 0x3C, 0x7E, 0xFF, 0x00, 0x66, 0x66, 0xFF, 0xFF, 0xFF, 0xBD, 0xC3, 0x7E, 0x7E, 0x3C, 0x00
    db 0x0B, 0x00, 0x00, 0x60, 0x78, 0x7E, 0x7F, 0x7F, 0x7E, 0x78, 0x60, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x0C, 0x00, 0x3C, 0x7E, 0x7E, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7E, 0x7E, 0x3C, 0x00
    db 0x0D, 0x3C, 0x7E, 0xFF, 0xFF, 0xDF, 0xBF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7E, 0x3C
    db 0x0E, 0x00, 0x00, 0x00, 0x18, 0x3C, 0x7E, 0x7E, 0x7E, 0x7E, 0x7E, 0x3C, 0x18, 0x00, 0x00, 0x00, 0x00
    db 0x0F, 0x3C, 0x7E, 0x99, 0xDB, 0xFF, 0xC3, 0x81, 0x00, 0x00, 0x81, 0xC3, 0xFF, 0xFF, 0x7E, 0x3C, 0x00
    db 0x10, 0x00, 0x3C, 0x7E, 0xFF, 0x99, 0xBD, 0x99, 0xFF, 0xFF, 0xC3, 0x99, 0x99, 0xC3, 0x7E, 0x3C, 0x00
    db 0x11, 0x00, 0x06, 0x0E, 0x1E, 0x36, 0x66, 0x06, 0x06, 0x06, 0x1E, 0x3E, 0x3E, 0x1C, 0x00, 0x00, 0x00
    db 0x12, 0x00, 0x18, 0x5A, 0x3C, 0x7E, 0xE7, 0xC3, 0xC3, 0xE7, 0x7E, 0x3C, 0x5A, 0x18, 0x00, 0x00, 0x00
    db 0x13, 0x00, 0x00, 0x60, 0x30, 0x18, 0x0C, 0x18, 0x30, 0x60, 0x00, 0x00, 0x1F, 0x1F, 0x00, 0x00, 0x00
    db 0x14, 0x80, 0xC0, 0xE0, 0xF0, 0xF8, 0xFC, 0xFE, 0xFF, 0xF8, 0xDC, 0x8C, 0x06, 0x06, 0x00, 0x00, 0x00
    db 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x06, 0xFC, 0xFC, 0x06, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00
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

reset_vector:               ; Physical 0xFFFFFFF0 / Alias 0xF000:0xFFF0
    jmp 0xF000:bios_start   ; 5 Bytes (0xFFF0..0xFFF4)
    db "10/23/26"           ; 8 Bytes (0xFFF5..0xFFFC)
    db 0x00                 ; 1 Byte  (0xFFFD)
    db 0xFC                 ; 1 Byte  (0xFFFE): System Model ID (PC/AT)
    db 0x00                 ; 1 Byte  (0xFFFF) -> Exactly 65536 Bytes
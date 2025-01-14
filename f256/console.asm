; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu    "w65c02"

            .namespace  platform
console     .namespace

            .section    dp

src         .word       ?
dest        .word       ?
count       .word       ?

cur_x       .byte       ?
cur_y       .byte       ?
color       .byte       ?
ptr
line        .word       ?   ; line ptr
            .send

            .section    kmem
mouse_x     .byte       ?
mouse_y     .byte       ?
            .send            

            ;.section    kernel
            .section    global
ROWS = 60
COLS = 80


; IO PAGE 0
TEXT_LUT_FG      = $D800
TEXT_LUT_BG	 = $D840
; Text Memory
TEXT_MEM         = $C000 	; IO Page 2
COLOR_MEM        = $C000 	; IO Page 3


mouse
            lda     mouse_x
            clc
            adc     kernel.event.entry.mouse.delta.x,y
            sta     mouse_x

            lda     mouse_y
            clc
            adc     kernel.event.entry.mouse.delta.y,y
            sta     mouse_y

            jsr     kernel.event.free

            lda     #'*'
            sta     VKY_TXT_CURSOR_CHAR_REG

            lda     #$10
            sta     VKY_TXT_CURSOR_COLR_REG 
            
            lda     mouse_x
            lsr     a
            lsr     a
            sta     VKY_TXT_CURSOR_X_REG_L
            stz     VKY_TXT_CURSOR_X_REG_H

            lda     mouse_y
            lsr     a
            lsr     a
            sta     VKY_TXT_CURSOR_Y_REG_L
            stz     VKY_TXT_CURSOR_Y_REG_H

            lda     #Vky_Cursor_Enable | Vky_Cursor_Flash_Rate0 | 8
            sta     VKY_TXT_CURSOR_CTRL_REG
            stz     VKY_TXT_START_ADD_PTR

            rts

asr         .macro
            cmp     #$80
            ror     a
            .endm

mouse_update_x
            lda     kernel.event.entry.mouse.delta.x
            .asr
            .asr
            clc
            adc     mouse_x    
            bmi     _zx
            cmp     #80
            bcc     _ok
            lda     #79
_ok         sta     mouse_x                 
            rts
_zx         lda     #0
            bra     _ok
            
mouse_update_y
            lda     kernel.event.entry.mouse.delta.y
            .asr
            .asr
            clc
            adc     mouse_y
            bmi     _zx
            cmp     #60
            bcc     _ok
            lda     #59
_ok         sta     mouse_y                 
            rts
_zx         lda     #0
            bra     _ok
            
spin
            inc     kernel.thread.lock
            lda     $1
            pha
            lda     #2
            sta     io_ctrl
            lda     kernel.ticks
            sta     $c000,x
            ;inc     $c000,x
            pla
            sta     io_ctrl
            dec     kernel.thread.lock
            rts

poke rts
            inc     kernel.thread.lock
            stz     $1
            inc     $1
            inc     $1
            sta     $c000+160,x
            stz     $1
            dec     kernel.thread.lock
            rts


init ;rts
            lda     #$80
            sta     mmu_ctrl
            lda     mmu+7
            cmp     #$80
            lda     #$20
            bcs     _color
            lda     #$10
_color      sta     color
            jsr     TinyVky_Init
            jsr     load_font
            jsr     cls
            ; ldy     #8
            ; ldx     #0
            ; jsr     gotoxy     
            stz     $1
            lda     #10
            sta     mouse_x
            sta     mouse_y
            jsr     init_mouse
            rts

welcome:
            jsr     cls
            jsr     part1
            jsr     part2
            rts
            
part1
            ldy     #0
_loop       lda     _msg,y
            beq     _out
            jsr     puts
            iny
            bra     _loop
_out    
            rts
_msg
            .text   "Foenix F256 by Stefany Allaire", $0a
            .text   "https://c256foenix.com/",$0a
            .text   $0a
            .text   "TinyCore MicroKernel", $0a
            .text   "Copyright 2025 Jessie Oberreuter", $0a
            .text   "Gadget@HackwrenchLabs.com",$0a
            .text   "F256 Edition built ", DATE_STR
            .text   $0a, $0a, $00
            
part2
            ldy     #0
_loop       lda     _msg,y
            beq     _out
            jsr     puts
            iny
            bra     _loop
_out    
            rts
_msg
            .text   "Fat32 https://github.com/commanderx16/x16-rom", $0a
            .text   "Copyright 2020 Frank van den Hoef, Michael Steil", $0a
            .byte   $0a, $0


cls
            lda     $1
            pha
            phx
            phy


            lda     #2
            sta     io_ctrl
            lda     #' '
            jsr     _fill

            lda     #3
            sta     io_ctrl
            lda     color
            jsr     _fill
            
            ldx     #0
            ldy     #0
            jsr     gotoxy

            ply
            plx
            pla
            sta     $1
            rts

_fill
            ldy     #$c0
            sty     line+1
            stz     line+0
            ldx     #$13
            ldy     #0
_loop       sta     (line),y
            iny
            bne     _loop
            inc     line+1
            dex
            bne     _loop
            rts
            
                        
gotoxy
            stx     cur_x
            sty     cur_y

            stz     line+1
            tya
            asl     a
            asl     a
            rol     line+1
            adc     cur_y
            asl     a
            rol     line+1
            asl     a
            rol     line+1
            asl     a
            rol     line+1
            asl     a
            rol     line+1
            sta     line+0

            lda     line+1
            adc     #$c0
            sta     line+1
            
            rts

Mstr_Ctrl_Turn_Off_Sync = 8
Mstr_Ctrl_FONT_Show_BG_in_Overlay = 16

TinyVky_Init:

            lda     $1
            pha

            stz     io_ctrl
        
          ; Init MASTER_CTRL_REG_L: text mode w/ optional gamma
            ;jsr     platform.dips.read
         lda #0
            and     #platform.dips.GAMMA
            cmp     #1  ; Set carry if gamma is set
            lda     #Mstr_Ctrl_Text_Mode_En;
            bcc     _store
            ora     #Mstr_Ctrl_GAMMA_En
_store      sta     MASTER_CTRL_REG_L
            lda     MASTER_CTRL_REG_L

            stz     BORDER_CTRL_REG
            stz     BORDER_COLOR_B
            stz     BORDER_COLOR_G
            stz     BORDER_COLOR_R
            
          ; We'll manage our own cursor
            stz     VKY_TXT_CURSOR_CTRL_REG

.if false   ; Causes crash?
            stz     BORDER_X_SIZE
            stz     BORDER_Y_SIZE
.endif
            ldx     #0
_fgloop     lda     _palette,x
            sta     TEXT_LUT_FG,x
            sta     TEXT_LUT_BG,x
            inx
            cpx     #64
            bne     _fgloop
 ;bra _done            
            jsr     init_graphics_palettes
_done
            clc
            pla
            sta     $1
            rts

_palette
            .dword  $000000
            .dword  $ffffff
            .dword  $880000
            .dword  $aaffee
            .dword  $cc44cc
            .dword  $00cc55
            .dword  $0000aa
            .dword  $dddd77
            .dword  $dd8855
            .dword  $664400
            .dword  $ff7777
            .dword  $333333
            .dword  $777777
            .dword  $aaff66
            .dword  $0088ff
            .dword  $bbbbbb

init_graphics_palettes

            phx
            phy

          ; Save I/O page
            ldy     $1

          ; Switch to I/O Page 1 (font and color LUTs)
            lda     #1
            sta     $1

          ; Init ptr
            stz     ptr+0
            lda     #$d0
            sta     ptr+1

            ldx     #0          ; Starting color byte.
_loop
          ; Write the next color entry
            jsr     write_bgra
            inx

          ; Advance the pointer; X will wrap around on its own

            lda     ptr
            adc     #4
            sta     ptr
            bne     _loop

            lda     ptr+1
            inc     a
            sta     ptr+1
            cmp     #$e0
            bne     _loop

          ; Restore I/O page
            sty     $1

            ply
            plx
            rts
            
write_bgra
    ; X = rrrgggbb
    ; A palette entry consists of four consecutive bytes: B, G, R, A.

            phy
            ldy     #3  ; Working backwards: A,R,G,B

          ; Write the Alpha value
            lda     #255
            jsr     _write

          ; Write the RGB values
            txa
_loop       dey
            bmi     _done
            jsr     _write
            bra     _loop

_done       ply
            clc
            rts

_write
          ; Write the upper bits to (ptr),y
            pha
            and     #%111_00000
            sta     (ptr),y
            pla

          ; Shift in the next set of bits (blue truncated, alpha zero).
            asl     a
            asl     a
            asl     a

            rts

init_mouse
            ldx     #0
            stz     $1
            stz     $D6e2
            stz     $D6e3
            stz     $D6e4
            stz     $D6e5
_loop       lda     _ptr,x
            sta     $cc00,x
            inx
            bne     _loop
            lda     #0; #$01
            sta     $d6e0
            rts
_ptr
            .text $00,$01,$01,$00,$00,$00,$00,$00,$01,$01,$01,$00,$00,$00,$00,$00
            .text $01,$FF,$FF,$01,$00,$00,$01,$01,$FF,$FF,$FF,$01,$00,$00,$00,$00
            .text $01,$FF,$FF,$FF,$01,$01,$55,$FF,$01,$55,$FF,$FF,$01,$00,$00,$00
            .text $01,$55,$FF,$FF,$FF,$FF,$01,$55,$FF,$FF,$FF,$FF,$01,$00,$00,$00
            .text $00,$01,$55,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$01,$FF,$FF,$01,$00,$00
            .text $00,$00,$01,$55,$FF,$FF,$FF,$FF,$01,$FF,$FF,$01,$FF,$01,$00,$00
            .text $00,$00,$01,$01,$55,$FF,$FF,$FF,$FF,$01,$FF,$FF,$FF,$01,$00,$00
            .text $00,$00,$01,$55,$01,$55,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$01,$01,$00
            .text $00,$00,$01,$55,$55,$55,$FF,$FF,$FF,$FF,$FF,$FF,$01,$FF,$FF,$01
            .text $00,$00,$00,$01,$55,$55,$55,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$01
            .text $00,$00,$00,$00,$01,$55,$55,$55,$55,$55,$01,$FF,$FF,$55,$01,$00
            .text $00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$55,$FF,$55,$01,$00,$00
            .text $00,$00,$00,$00,$00,$00,$00,$00,$01,$55,$55,$55,$01,$00,$00,$00
            .text $00,$00,$00,$00,$00,$00,$00,$00,$01,$55,$55,$01,$00,$00,$00,$00
            .text $00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$00,$00,$00,$00,$00
            .text $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00                        
            
            


long_move            
            phx
            phy

            ldy     #0
            ldx     count+1
            beq     _small

_large      lda     (src),y
            sta     (dest),y
            iny
            bne     _large
            inc     src+1
            inc     dest+1
            dex
            bne     _large
            bra     _small

_loop       lda     (src),y
            sta     (dest),y

            iny
_small      cpy     count
            bne     _loop

            ply
            plx
            rts

puts
        pha
        phx
        phy

        ldy     io_ctrl
        phy
        jsr     _puts
.if false
        lda     #$7f
        ldy     cur_x
        sta     (ptr),y        
.else
        stz     $1

        lda     cur_x
        sta     VKY_TXT_CURSOR_X_REG_L
        stz     VKY_TXT_CURSOR_X_REG_H
        lda     cur_y
        sta     VKY_TXT_CURSOR_Y_REG_L
        stz     VKY_TXT_CURSOR_Y_REG_H
 
        lda #$db
        lda #32+128
        sta VKY_TXT_CURSOR_CHAR_REG         ; 160 is 128+32 so inverse space. ($D012)
        lda #28
        sta VKY_TXT_CURSOR_COLR_REG 

        lda     #Vky_Cursor_Enable | Vky_Cursor_Flash_Rate0 | 8
    lda #0
        sta     VKY_TXT_CURSOR_CTRL_REG
        stz     VKY_TXT_START_ADD_PTR
.endif        
        ply
        sty     io_ctrl

        ply
        plx
        pla
        rts

_puts
        ldy     #2
        sty     $1

        cmp     #$0a
        beq     _lf
        cmp     #12
        beq     _cls
        bra     _std
        
_cls
        jmp     cls

_lf     
        ldy     cur_y
        iny
        cpy     #ROWS
        beq     _scroll
        
        sty     cur_y
        lda     ptr
        clc
        adc     #COLS
        sta     ptr
        lda     #0
        adc     ptr+1
        sta     ptr+1

_cr
        stz     cur_x
        rts

_std    ldy     cur_x
        sta     (ptr),y
        iny
        cpy     #COLS
        beq     _crlf
        sty     cur_x
        rts

_crlf   jsr     _cr
        jmp     _lf

_scroll
        stz     cur_x
        lda     #$c0
        sta     src+1
        sta     dest+1

        lda     #80
        sta     src
        stz     dest

        lda     #<COLS*(ROWS-1)
        sta     count
        lda     #>COLS*(ROWS-1)
        sta     count+1

        jmp     long_move

_pause
        sei
        bra     _pause

load_font: rts
my_font: rts

            .send
            .endn
            .endn

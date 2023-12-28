; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

        .cpu    "w65c02"

        .namespace  hardware

kbd2    .namespace
        
            .section    kmem
e0          .byte       ?   ; e0 prefix received.
e1          .byte       ?   ; e1 prefix received.
released    .byte       ?   ; release prefix received 
meta        .fill 16    ;   Room for the 9 mode keys 16..31.
debug       .byte       ?
            .send
            
            .section kernel

init
            stz     e0
            stz     e1
            stz     released
            stz     debug        
    
            phx
            ldx #0
_loop       stz meta,x
            inx
            cpx #16
            bne _loop
            plx            

            clc
            rts


accept

        ; Handle prefix codes
        
          ; Key released
            cmp     #$f0
            beq     _f0

          ; Extended prefix 0
            cmp     #$e0
            beq     _e0

          ; Extended prefix 1
            cmp     #$e1
            beq     _e1

          ; Anything else high appears to be bogus
            cmp     #$84
            bcs     _drop

        ; Handle keys based on prefix

            ldy     e0
            bne     _ext0

            ldy     e1
            bne     _ext1
            
            tay
            lda     keymap,y

_raw
            jsr     send

_drop       
            stz     e0
            stz     e1
            stz     released
            rts

_e0         
            sta     e0
            rts

_e1         
            sta     e1
            rts

_f0         
          ; This value will convert a PRESSED into a RELEASED under xor.
            lda     #kernel.event.key.RELEASED ^ kernel.event.key.PRESSED
            sta     released
            rts

_ext1
        ; Map keys prefixed with $e1
            cmp     #$14
            bne     _drop
            lda     #PAUSE
            bra     _raw

_ext0
        ; Map keys prefixed with $e0.

            ldy     #0
_loop       cmp     _etab,y
            beq     _found
            iny
            iny            
            cpy     #_end
            bne     _loop

          ; Unknonw suffix; drop.
            bra     _drop

_found      lda     _etab+1,y
            bra     _raw

_etab       
            .byte   $11, RALT
            .byte   $14, RCTRL
            .byte   $1f, LMETA           
            .byte   $27, RMETA           
            .byte   $4a, KDIV
            .byte   $5a, KENTER
            .byte   $69, END
            .byte   $6b, LEFT 
            .byte   $6c, HOME
            .byte   $70, INS
            .byte   $71, DEL
            .byte   $72, DOWN
            .byte   $74, RIGHT
            .byte   $75, UP
            .byte   $7a, PDN
            .byte   $7d, PUP
_end        = * - _etab


send
          ; Allocate an event; drop keys if out of events.
            jsr     kernel.event.alloc
            bcs     _done
            
          ; Set the raw code
            sta     kernel.event.entry.key.raw,y

          ; Set the cooked (ascii) code
            jsr     ascii
            sta     kernel.event.entry.key.ascii,y

          ; Set a flag bit for non-ascii keys
            lda     #0
            ror     a
            sta     kernel.event.entry.key.flags,y

          ; Set the event type to key.PRESSED or key.RELEASED
            lda     #kernel.event.key.PRESSED
            eor     released
            sta     kernel.event.entry.type,y
            
          ; Set the keyboard ID:
            lda     #1
            sta     kernel.event.entry.key.keyboard

          ; Send the event
            jmp     kernel.event.enque
_done
            rts

ascii
    ; This function needs to do all of the magic meta-key tracking
    ; IN: A = raw code; 'released' set if this is a release.

            phy

          ; Handle meta-key pressed/released
            cmp     #16
            bcc     _meta
            
          ; Special-case nav/func keys
            tay
            bpl     _shift
            jsr     special
            cmp     #$80    ; Set carry if still non-ascii
            bra     _done

_shift    ; Handle shift
            lda     meta+LSHIFT
            ora     meta+RSHIFT
            beq     _ctrl
            tya
            jsr     shift
            tay

_ctrl     ; CTRL for ASCII: project codes down to $00-$1F
            lda     meta+LCTRL
            ora     meta+RCTRL
            beq     _alt
            tya
            and     #$1f
            tay
            
_alt      ; ALT for ASCII: set the high bit
            tya
            asl     a
            tay
            lda     meta+LALT
            ora     meta+RALT
            cmp     #1
            tya
            ror     a
            clc

_done
            ply
            rts
            
_meta
        ; set/clear the associated flag

          ; Y->table entry
            tay                 

          ; Carry set on release
            lda     released
            cmp     #1          

          ; A = 1 on press / 0 on release
            rol     a
            and     #1
            eor     #1

          ; Store
            sta     meta,y  

          ; Return "Not ASCII"
            lda     #0 
            sec
            bra     _done

shift
    ; Returns the shifted code for the given ASCII character.
    ; IN/OUT: A = character.
    
            cmp     #'a'
            bcc     _find
            cmp     #'z'+1
            bcs     _find
            eor     #$20
            rts
_find
            ldy     #0
_loop       
            cmp     _map,y
            beq     _found
            iny
            iny
            cpy     #_end
            bne     _loop

          ; Any non-alpha key with no entry doesn't change.
            rts

_found      lda     _map+1,y
            rts
_map
            .byte   '1', '!'
            .byte   '2', '@'
            .byte   '3', '#'
            .byte   '4', '$'
            .byte   '5', '%'
            .byte   '6', '^'
            .byte   '7', '&'
            .byte   '8', '*'
            .byte   '9', '('
            .byte   '0', ')'
            .byte   '-', '_'
            .byte   '=', '+'

            .byte   '[', '{'
            .byte   ']', '}'
            .byte   $5c, '|'

            .byte   ';', ':'
            .byte   $27, $22

            .byte   ',', '<'
            .byte   '.', '>'
            .byte   '/', '?'
            .byte   '`', '~'
            
_end        = * - _map
            
special
    ; Returns ASCII encodings for special characters
    ; IN/OUT: A = character.
    
            ldy     #0
_loop       
            cmp     _map,y
            beq     _found
            iny
            iny
            cpy     #_end
            bne     _loop
_default
          ; Return the natural code by default            
            rts

_found      lda     _map+1,y
            rts
_map
            .byte   HOME,   'A'-64
            .byte   END,    'E'-64
            .byte   UP,     'P'-64
            .byte   DOWN,   'N'-64
            .byte   LEFT,   'B'-64
            .byte   RIGHT,  'F'-64
            .byte   DEL,    'D'-64
            .byte   ESC,    27
            .byte   TAB,    'I'-64
            .byte   ENTER,  'M'-64
            .byte   PUP,    'Z'-64
            .byte   PDN,    'V'-64
            .byte   BKSP,   'H'-64
            .byte   KPLUS,  '+'
            .byte   KMINUS, '-'
            .byte   KTIMES, '*'
            .byte   KDIV,   '/'
            .byte   KENTER, 'M'-64
            .byte   KPOINT, '.'
            .byte   K0,     '0'
            .byte   K1,     '1'
            .byte   K2,     '2'
            .byte   K3,     '3'
            .byte   K4,     '4'
            .byte   K5,     '5'
            .byte   K6,     '6'
            .byte   K7,     '7'
            .byte   K8,     '8'
            .byte   K9,     '9'
            
_end        = * - _map
            

keymap:

            .byte 0, F9, 0, F5, F3, F1, F2, F12
            .byte 0, F10, F8, F6, F4, TAB, '`', 0
            .byte 0, LALT, LSHIFT, 0, LCTRL, 'q', '1', 0
            .byte 0, 0, 'z', 's', 'a', 'w', '2', 0
            .byte 0, 'c', 'x', 'd', 'e', '4', '3', 0
            .byte 0, ' ', 'v', 'f', 't', 'r', '5', 0
            .byte 0, 'n', 'b', 'h', 'g', 'y', '6', 0
            .byte 0, 0, 'm', 'j', 'u', '7', '8', 0
            .byte 0, ',', 'k', 'i', 'o', '0', '9', 0
            .byte 0, '.', '/', 'l', ';', 'p', '-', 0
            .byte 0, 0, "'", 0, '[', '=', 0, 0
            .byte CAPS, RSHIFT, ENTER, ']', 0, '\', 0, 0
            .byte 0, 0, 0, 0, 0, 0, BKSP, 0
            .byte 0, K1, 0, K4, K7, 0, 0, 0
            .byte K0, KPOINT, K2, K5, K6, K8, ESC, NUM
            .byte F11, KPLUS, K3, KMINUS, KTIMES, K9, SCROLL, 0
            .byte 0, 0, 0, F7, SYSREQ, 0, 0, 0, 0

            .send
            .endn
            .endn

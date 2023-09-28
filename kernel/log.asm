; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu        "w65c02"
            
            .namespace  kernel
log         .namespace

kargs       .struct
log         .byte       ?   ; Log to render.
buf         .word       ?   ; Target buffer.
length      .byte       ?   ; Buffer length.
used        .byte       ?   ; Buffer bytes used.
            .ends

RING_SIZE   =   16

            .section    dp
head        .byte       ?
tail        .byte       ?
ptr
ptr_l       .byte       ?
ptr_h       .byte       ?
            .send            

            .section    kmem
ring        .fill       RING_SIZE
arg         .byte       ?
tmp         .byte   ?
            .send

entry       .namespace
            .virtual    Tokens
device      .byte   ?
string      .byte   ?
arg         .byte   ?
            .endv
            .endn

            .section    global


init
            lda     #0
            sta     head
            sta     tail
            clc
            rts

dev_message
    ; A = string, X = dev, Y = arg
    
            inc     kernel.thread.lock
            sty     tmp

            jsr     kernel.token.alloc
            bcs     _out

            sta     entry.string,y
            txa
            sta     entry.device,y
            lda     tmp
            sta     entry.arg,y
            
            jsr     insert
            bcc     _out
            jsr     kernel.token.free
            sec
_out        
            ldy     tmp
            dec     kernel.thread.lock
            rts

insert
    ; Inserts the value in Y (a token) into the ring.
    ; Carry clear on success.  Modifies A.
    
            inc     kernel.thread.lock
            phx

            ldx     head
            tya
            sta     ring,x
            inx
            cpx     #RING_SIZE
            bne     _cmp
            ldx     #0
_cmp        cpx     tail
            sec
            beq     _out
            stx     head
            clc
_out        
            plx
            dec     kernel.thread.lock            
            rts


remove
            phx
            ldx     tail
            cpx     head
            sec
            beq     _out
            ldy     ring,x
            inx
            cpx     #RING_SIZE
            bne     _save
            ldx     #0
_save       
            stx     tail
            clc
_out
            plx
            rts            

next
            jsr     remove
            bcs     _done
            jsr     print_log
            jsr     kernel.token.free
_done
            rts

render
            pha
            phy
            
            lda     kargs.buf,x
            pha

            ldy     kargs.log,x
            stz     kargs.used,x
            jsr     print_log

            ldy     kargs.log,x
            jsr     kernel.token.free

            pla
            sta     kargs.buf,x

            ply
            pla
            clc
            rts
            
print_log
            lda     entry.arg,y
            sta     arg

            lda     entry.device,y
            beq     _msg

            phx
            ldx     entry.device,y
            lda     #kernel.device.get.CLASS
            jsr     kernel.device.dev.get
            plx
            jsr     print_string
            jsr     print_space

            phx
            ldx     entry.device,y
            lda     #kernel.device.get.DEVICE
            jsr     kernel.device.dev.get
            plx
            jsr     print_string
            jsr     print_space

            phx
            ldx     entry.device,y
            lda     #kernel.device.get.PORT
            jsr     kernel.device.dev.get
            plx
            jsr     print_string
            jsr     print_space

_msg
            lda     entry.string,y
            jsr     print_string
 rts
            lda     #$0a
            jmp     platform.console.puts


print_string
    ; Prints the string at the str handle in A.
            phx
            tax
            lda     Strings+0,x
            sta     ptr_l
            lda     Strings+1,x
            sta     ptr_h
            plx
            jmp     puts

print_space
            lda     #' '
            jmp     append

puts
    ; Print string in (ptr).
            phy
            ldy     #0
_loop
            lda     (ptr),y
            beq     _done
            cmp     #'#'
            beq     _arg
            jsr     append
_next       iny
            bra     _loop
_arg
            lda     arg
            lsr     a            
            lsr     a            
            lsr     a            
            lsr     a
            jsr     _hex
            lda     arg
            and     #$0f
            jsr     _hex
            bra     _next
_hex
            cmp     #10
            bcs     _char
            ora     #'0'
            jmp     append
_char       
            adc     #'a'-11
            jmp     append
_done
            clc
            ply
            rts
                                    
append
            sta     (kargs.buf,x)
            inc     kargs.buf+0,x
            bne     _out
            inc     kargs.buf+1,x
_out            
            inc     kargs.used,x
            rts

            .send
            .endn
            .endn
            

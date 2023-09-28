; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu    "r65c02"

            .namespace  kernel
stream      .namespace

            .section    pages
Streams     .fill       256
            .send

entry       .namespace
            .virtual    Streams ; TODO: Could prolly fit in 8 or 12.
next        .byte       ?
driver      .byte       ?
device      .byte       ?
partition   .byte       ?
channel     .byte       ?
state       .byte       ?
status      .byte       ?   ; See constants below
cookie      .byte       ?   ; user provided
eof         .byte       ?
delay       .byte       ?
pos         .dword      ?   ; current position in stream
            .endv
NEW         =   $00
READ        =   $01
WRITE       =   $02
ERROR       =   $03
EOF         =   $80
            .endn

            .section    kmem
streams     .byte       ?       ; just one for now :).
            .send

            .section    kernel


init
            stz     streams
            jsr     zero_block
            lda     #16
            clc
_loop       jsr     free
            adc     #16
            bne     _loop
            clc
            rts         

zero_block
            phx
            ldx     #0
_loop       stz     Streams,x
            inx
            bne     _loop
            plx
            rts

alloc
    ; OUT A = stream or error
    ; These are presently synchronous, so no locking.
            phy
            ldy     streams
            sec
            beq     _out
            lda     entry.next,y
            sta     streams
            tya
            clc            
_out        ply
            rts

free
    ; These are presently synchronous, so no locking.
            phy
            tay
            lda     streams
            sta     entry.next,y
            sty     streams
            tya
            jsr     _zero
            ply
            rts
_zero
            phx
            tax
            inx     ; Don't zero the link
            ldy     #15
_loop       stz     Streams,x
            inx
            dey
            bne     _loop
            plx
            rts
            
            .send

            .endn
            .endn

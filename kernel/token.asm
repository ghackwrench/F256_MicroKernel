; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu        "w65c02"
            
            .section    pages
Tokens      .fill       256
            .send          

            .namespace  kernel
token       .namespace


entry       .namespace
            .virtual    Tokens
data        .fill       3
next        .byte       ?
end         .endv
size =      end - Tokens
            .endn
            
            .section    kmem
entries     .byte       ?       ; free list
count       .byte       ?
            .send
            
            .section    kernel

init
            stz     entries
            stz     count
            lda     #0
_loop       tay
            jsr     free
_next       clc
            adc     #entry.size
            bne     _loop
            
            clc
            rts

alloc
    ; Y <- next token, or carry set.
    ; Thread safe.
            pha
 phx
 lda count
 tax
 lda #' '
 dec count
 jsr platform.console.poke
 plx 

            php
            sei
            ldy     entries
            beq     _empty
            lda     entry.next,y
            sta     entries
            plp
            pla
            clc
            rts
_empty      plp
            pla
            sec
            rts

free
    ; Y = token to free
    ; Thread safe
            pha
 phx
 lda count
 tax
 lda #'x'
 jsr platform.console.poke
 inc count
 plx
            php
            sei
            lda     entries
            sta     entry.next,y
            sty     entries
            plp
            pla
            clc
            rts

            .send
            .endn
            .endn


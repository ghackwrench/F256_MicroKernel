; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu        "w65c02"
            
            .namespace  kernel
page        .namespace

            .section    dp
ptr         .word       ?
            .send
            
            .section    kmem
entries     .byte       ?       ; free list
count       .byte       ?
            .send
            
            .section    kernel

init
    ; A = bank to pool
            stz     entries
            stz     count
_loop       jsr     free
            inc     a
            bit     #$1f
            bne     _loop
            clc
            rts

            
alloc_a
    ; A <- free page, or carry set on error
            php
            sei
            lda     entries
            beq     _empty
            stz     ptr+0
            sta     ptr+1
            lda     (ptr)
            sta     entries
            lda     ptr+1
            plp
            clc
            rts
_empty      
            plp
            sec
            rts            
            

free
    ; A = page to free
.if false    
    ; TODO: zero
        pha
        phx
        lda count
        clc
        adc #160
        tax
        lda #'*'
        jsr platform.console.poke
        plx
        pla
        inc count
.endif
            php
            sei
            stz     ptr+0
            sta     ptr+1
            lda     entries
            sta     (ptr)
            lda     ptr+1
            sta     entries
            plp
            rts

            .send
            .endn
            .endn


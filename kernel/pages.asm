; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu        "w65c02"
            
            .namespace  kernel
page        .namespace


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
            phy
            php
            sei
            ldy     entries
            beq     _empty
            stz     irq_tmp+0
            sty     irq_tmp+1
            lda     (irq_tmp)
            sta     entries
            tya
            plp
    pha
    phx
    dec count
    lda count
    clc
    adc #160
    tax
    lda #' '
    jsr platform.console.poke
    plx 
    pla
            ply
            clc
            rts
_empty      
            plp
            ply
            sec
            rts            
            

free
    ; A = page to free
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

            php
            sei
            stz     irq_tmp+0
            sta     irq_tmp+1
            lda     entries
            sta     (irq_tmp)
            lda     irq_tmp+1
            sta     entries
            plp
            rts

            .send
            .endn
            .endn


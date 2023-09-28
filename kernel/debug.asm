; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

        .cpu    "6502"  ; Try to keep this one generic

        .namespace  kernel
        .section    kernel

putch   jmp platform.puts

print_cr
        php
        pha
        lda     #$0a
        jsr     putch
        pla
        plp
        rts

print_space
        php
        pha
        lda     #' '
        jsr     putch
        pla
        plp
        rts

print_word
        php
        pha
        lda     1,y
        jsr     print_byte
        lda     0,y
        jsr     print_byte
        pla
        plp
        rts

print_byte
        php
        pha
        pha
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        jsr     print_digit
        pla
        and     #$0f
        jsr     print_digit
        pla
        plp
        rts

print_digit
        php
        pha
        cmp     #10
        bcs     _hex
        adc     #'0'
_put    jsr     putch
        pla
        plp
        rts
_hex    adc     #'a' - 10 - 1
        bcc     _put    
        
        .send
        .endn

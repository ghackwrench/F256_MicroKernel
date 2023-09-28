; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu    "65c02"

startup     .namespace

kargs       .struct
log         .byte       ?   ; Log to render.
buf         .word       ?   ; Target buffer.
length      .byte       ?   ; Buffer length.
used        .byte       ?   ; Buffer bytes used.
            .ends

            .section    dp
args        .dstruct    kargs
mark        .byte       ?
            .send

            .section    pages
buf         .fill       256
            .send

            .section    kmem
event       .fill       16
            .send            

            .section    global

wait
            lda     #>buf
            sta     args.buf+1
            stz     args.buf+0

            lda     kernel.ticks+1
            sta     mark
_loop
          ; Log events
            jsr     kernel.log.remove   ; handle in Y
            bcc     _log

            lda     kernel.ticks+1
            sec
            sbc     mark
            cmp     #2
            bcc     _loop
_done  
            rts
_log
            sty     args.log
            stz     args.buf
            lda     #255
            sta     args.length
            ldx     #args
            jsr     kernel.log.render

            lda     #0
            ldy     args.used
            sta     (args.buf),y
            jsr     print_string
            lda     #10
            jsr     platform.console.puts
            bra     _loop

print_string
            ldy     #0
_loop       
            lda     (args.buf),y
            beq     _out
            jsr     platform.console.puts
            iny
            bra     _loop
_out
            clc
            rts            


            .send
            .endn

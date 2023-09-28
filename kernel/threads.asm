; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

        .cpu        "w65c02"

        .namespace  kernel
        
thread  .namespace
           
        .section    dp
start   .byte   ?   ; Set to request servicing.
running .byte   ?   ; Set by the IRQ handler while the service is running.
lock    .byte   ?
        .send        

        .section    kernel

init
        stz     running
        stz     start
        rts        

service
        jmp     kernel.net.process

yield
        wai
        rts


        .send
        .endn
        .endn

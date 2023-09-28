; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

        .cpu    "w65c02"

        .namespace  platform
clock   .namespace

        .section    kernel2
        
rtc     .hardware.rtc_bq4802

init
        jmp     rtc.init

        .send
        .endn
        .endn
        

; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu        "6502"
            
            .namespace  kernel

err         .struct
BUSY        .word   err_busy
REQUEST     .word   err_request
            .ends

            .section    tables
Errors      .dstruct    err
            .align      256
            .send
            
            .section    kernel
err_busy    .null   "Device is busy."
err_request .null   "Unsupported request."
            .send


            .endn




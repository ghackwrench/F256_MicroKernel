; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu    "w65c02"

            .namespace  hardware
            .mkstr      via,        "6522  "
            .mkstr      keyboard,   "keyboard"
            .mkstr      jrk_init,   "F256k keyboard/joystick driver"
            .mkstr      cbm_init,   "CBM keyboard/joystick driver"
            .mkstr      jports,     "DB9Mx2"
            .endn

            .namespace  platform
keyboard    .namespace

            .section    kmem
ps2_0       .byte       ?
ps2_1       .byte       ?
            .send

            .section    kernel2

purple      .hardware.ps2.f256 $d640, 0, irq.ps2_0, hardware.purple_str
green       .hardware.ps2.f256 $d640, 1, irq.ps2_1, hardware.green_str
cbm_kbd     .platform.c64kbd.driver
jr_kbd      .platform.jr_kbd.driver

; d6a0 system control, 
; d6a7 computer id reads jr=02, k=$12

init
            jsr     cia_init
            jsr     ps2_init
            rts

cia_init
            stz     io_ctrl
            lda     $d6a7

            cmp     #$02
            beq     _cbm

            cmp     #$12
            beq     _jr

            clc
            rts
_cbm
            jmp     cbm_kbd.init
_jr
            jmp     jr_kbd.init           


ps2_init
            stz     ps2_0
            stz     ps2_1
            jsr     hardware.kbd2.init

            jsr     purple_init
            jsr     green_init
            rts
            
purple_init

            jsr     purple.init
            bcs     _out
            stx     ps2_0

            jsr     kernel.device.dev.open
            bcs     _out

_out        rts

green_init

            jsr     green.init
            bcs     _out
            stx     ps2_1

            jsr     kernel.device.dev.open
            bcs     _out

_out        rts

            .send
            .endn
            .endn
            

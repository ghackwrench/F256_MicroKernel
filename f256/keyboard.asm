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
k2_kbd      .platform.k2_kbd.driver

; d6a0 system control, 
; d6a7 computer id reads jr=02, k=$12
; d6a7 computer id reads k2=$11 - Stefany Sept 15th, 2024

init
            jsr     cia_init
            jsr     ps2_init
            rts

cia_init
            stz     io_ctrl
            lda     $d6a7
            and     #$1F        ; Stefany - Make sure to isolate the MID only

            cmp     #$02        ; Jr - No Local Keyboard
            beq     _cbm

            cmp     #$18        ; Jr2 - Jr II has also only the PS2, there is no way to use the VIA0 has CBM Keyboard though
            beq     _cbm            

            cmp     #$12        ; K - PS2 & Local Keyboard using VIA1 & VIA0
            beq     _jr

            cmp     #$11        ; Stefany - K2 Optical Keyboard
            beq     _k2         ; PS2 & Local Optical Keyboard using the hardware implementation of Keyboard Scanner
                                ; Optical Keyboard is far slower to respond so, hardware is used to eliminate the need for the code to wait for each row.
            clc
            rts

_cbm
            jmp     cbm_kbd.init

_jr
            jmp     jr_kbd.init
                                ; NEW STUFF - September 18th, 2024
_k2         lda     $DDC1       ; If the Unit is a K2, Then let's figure out which Keyboard is installed
            bmi     _jr         ; if the bit[7] is 1, then it is a Traditional Mechanical Keyboard, so it is like a F256K
                                ; Otherwise, it is the optical Keyboard
            jmp     k2_kbd.init

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
            

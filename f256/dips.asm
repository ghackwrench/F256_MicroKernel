; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu        "65c02"

            .namespace  platform
dips        .namespace

            .section    global

GAMMA       =   $80     ; 8 ; Monitor type (analog/digital)
HI_RES      =   $40     ; 7 ; Monitor sync (60/70)
VIAKBD      =   $20     ; 6 ; CBM keyboard is installed (or snd exp)
SIDS        =   $10     ; 5 ; SIDs are installed
WIFI        =   $08     ; 4 ; Feather WiFi installed
SLIP        =   $04     ; 3 ; Enable SLIP support
ADV_SD      =   $02     ; 2 ; Enable the rich but slow SD/SPI stack.
BOOT_MENU   =   $01     ; 1 ; Enable boot menu

read
    stz io_ctrl
    ; Returns the values of the dip switches in A.
    ; Assumes that we're in the system registers I/O map.

            lda     $d670   ; Read Jr dip switch register.
            eor     #$ff    ; Values are inverted.
            rts

.if false
$D6A0 System control
$D6A8 - $42 (B) 41 (A)
$D6A9 - $30
.endif
            .send
            .endn
            .endn

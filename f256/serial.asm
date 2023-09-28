; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

        .cpu    "w65c02"

        .namespace  platform
serial  .namespace

        .section    kmem
com0    .byte       ?       ; Serial device            
slip0   .byte       ?       ; SLIP device
midi0   .byte       ?       ; MIDI device
        .send

        .section    kernel

uart    .hardware.u16550    $d630, platform.serial.divtab, irq.serial, (128+32+16)

init 
        stz     io_ctrl     ; TODO: remove when this is the default

      ; Initialize the uart.
        jsr     uart.init
        bcs     _out
        stx     com0

      ; Select SLIP or MIDI based on the dip switches.
        jsr     platform.dips.read
        bit     #platform.dips.SLIP
        beq     _midi

_slip
      ; Set the local ip address
        jsr     set_local_ip

      ; Initialize the SLIP driver.
        jsr     kernel.net.slip.init
        bcs     _out
        stx     slip0
        stx     kernel.net.ipv4.router

      ; Open the SLIP device.
      ; Should prolly set the BPS on com0 first.
        lda     #>115200 ; BPS
     ;lda     #>19200 ; BPS
        ldy     com0
        jsr     kernel.device.dev.open
        bra     _out

_midi
      ; Initialize the MIDI driver.
        jsr     midi_init
        bcs     _out
        stx     midi0

      ; Open the uart with the MIDI handler.
        lda     #>31250 ; MIDI BPS
        ldy     com0
        jsr     kernel.device.dev.open
        bra     _out

_out    rts        

set_local_ip
        jsr     platform.dips.read
        bit     #platform.dips.WIFI
        beq     _done
        phy
        ldy     #0
_loop   lda     _wifi,y
        sta     kernel.net.ipv4.ip_addr,y
        iny
        cpy     #4
        bne     _loop
        ply
_done
        clc
        rts
_wifi   ; https://github.com/e1z0/esp_slip_router
        .byte   192,168,240,2   
        

midi_init
        sec     ; Driver not yet implemented.
        rts

divtab
    ; IN: A->BPS
    ; OUT: A:Y = divisor, or carry set on error.
    
        ldy     #0
_loop   cpy     #_end
        bcs     _out
        cmp     _table,y
        beq     _found
        iny
        iny
        iny
        bra     _loop
_found          
        lda     _table+1,y
        pha
        lda     _table+2,y
        ply
        clc
_out    
        rts
_table  ; TODO: recalc for 25.175MHz
        .byte   >300,       $72, $14    ; 5234.38->5234
        .byte   >600,       $39, $0a    ; 2617.19->2617
        .byte   >1200,      $1d, $05    ; 1308.59->1309
        .byte   >2400,      $8e, $02    ; 654.30->654
        .byte   >4800,      $47, $01    ; 327.15->327
        .byte   >9600,      $a4, $00    ; 163.57->164
        .byte   >19200,     $52, $00    ; 81.79->82
        .byte   >31250,     $32, $00    ; 50.25->50 (MIDI)
        .byte   >38400,     $2b, $00    ; 40.89->41
        .byte   >57600,     $1b, $00    ; 27.26->27
        .byte   >115200,    $0d, $00    ; 13.63->13
_end =  * - _table             
        

            .send
            .endn
            .endn
            
; The exeption to this rule is the Audio Section that works from fraction of 14.318Mhz, the interface is still 25.175Mhz, but there is a FIFO to break the different clock domain. the PSG are 3.57Mhz, the Extern SID is 1.000ish something (14.318/14).

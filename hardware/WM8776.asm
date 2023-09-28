; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu        "w65c02"

            .namespace  hardware


            .mkstr      wm8776, "WM8776"


wm8776      .macro      BASE = $D620

CODEC_DATA_LO   = \BASE+0
CODEC_DATA_HI   = \BASE+1
CODEC_WR_CTRL   = \BASE+2

self        .namespace
            .virtual    DevState
this        .byte       ?       ; self
bits        .byte       ?       ; device enable bits
            .endv
            .endn            

vectors     .kernel.device.mkdev    dev


init

      ; Allocate and save the device slot.
        jsr     kernel.device.alloc
        bcs     _err
        txa
        sta     self.this,x

      ; Start with all inputs disabled.
        lda     #0  ; All channels off
        jsr     send_channel_bits
        bcc     _done
        
        jsr     kernel.device.free
        sec
_err    rts

_done   jmp     kernel.device.install


dev_open
    ; A = set of devices to enable.
    ; Convenience function; not needed.

        jmp     send_channel_bits

dev_close
    ; Disable all audio sources.
        lda     #0
        jmp     send_channel_bits
        
dev_data
dev_fetch
dev_status
    ; The WM8776 doesn't generate interrupts.
    ; Could register a timer and probe for headphone events.
        rts


dev_send
        sec
        rts

dev_get
        phy

        ldy     #hardware.serial_str
        cmp     #kernel.device.get.CLASS
        beq     _found
        
        ldy     #hardware.uart_str
        cmp     #kernel.device.get.DEVICE
        beq     _found
        
        ldy     #hardware.db9_str
        cmp     #kernel.device.get.PORT
        beq     _found
        
        sec
        bra     _out

_found
        tya
        clc        
_out
        ply
        rts


dev_set
        cmp     #kernel.device.set.CH_ENABLE
        beq     channel_enable

        cmp     #kernel.device.set.CH_DISABLE
        beq     channel_disable
        
        cmp     #kernel.device.set.VOLUME
        beq     set_volume

        cmp     #kernel.device.set.REGISTER
        beq     send_command

        ldx     #kernel.err.REQUEST
        sec
        rts
        
set_volume
        clc
        rts

send_command
    ; Y->token
        phy

        lda     kernel.token.entry.data+1,y ; High
        pha
        lda     kernel.token.entry.data+0,y ; Low
        ply
        jsr     WM8776_send

        ply
        beq     _out
        jmp     kernel.token.free
_out
        rts


channel_enable
    ; Y = channel number

        jsr     channel_bit
        bcs     _out
        ora     self.bits,x
        bra     send_channel_bits
_out    rts

channel_disable
    ; Y = channel number

        jsr     channel_bit
        bcs     _out
        eor     #$ff
        and     self.bits,x
        bra     send_channel_bits
_out    rts

channel_bit
    ; Y = channel number
        cpy     #7
        bcs     _out

        lda     #1
_loop   dey
        beq     _out
        asl     a
        dey
        bra     _loop
        
_out    rts


send_channel_bits

      ; Save the bits.
        sta     self.bits,x

      ; Send the line mixer bits.
        lda     self.bits,x
        lsr     a
        lsr     a
        ldy     #%0010101_0     ; Input MUX control.
        jsr     WM8776_send     ; Ignore errors.
        
      ; Send the output MUX bits
        ldy     self.bits,x
        tya                     ; L5--L1=64--4, AUX=2, DAC=1
        and     #3              ; A[1:0] contains AUX and DAC
        cpy     #4              ; Carry set if any line bits are set
        bcc     _send           ; Just AUX/DAC
        ora     #4              ; Enable the line mixer input
_send   ldy     #%0010110_0     ; Output MUX control.
        jsr     WM8776_send
        
_out    rts


WM8776_send
    ; Y:A = address[7]:arg[9]

        sta     CODEC_DATA_LO
        tya
        sta     CODEC_DATA_HI

        ; TODO: timeout
        lda     #1
        sta     CODEC_WR_CTRL
_loop   lda     CODEC_WR_CTRL
        bit     #1
        bne     _loop

        clc
        rts

        .endm
        .endn

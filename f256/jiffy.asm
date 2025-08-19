; Jiffy implementation Copyright 2025 Matthias Brukner <mbrukner@gmail.com>
; SPDX-License-Identifier: GPL-3.0-only

            .cpu        "w65c02"


            .namespace  platform
jiffy       .namespace
            .section    kernel2

            .with platform.iec
JIFFY_DEBUG = IEC_DEBUG
DBG_CALL    .macro routine
            .if JIFFY_DEBUG
            jsr \routine
            .endif
            .endm

init        .proc
            rts
            .endproc

            ; ------------------------------------------- Jiffy transfers----
            ; Translation tables for sending out data, going from 4 bits to
            ; two bit pairs, aligned with IEC output register so it is easy
            ; and cheap to send out.

            ; Bit[0] IEC_DATA_o
            ; Bit[1] IEC_CLK_o

            ; HIGH nibble (7..4)
tx_high
            .byte   $0f, $0d, $0e, $0c, $07, $05, $06, $04
            .byte   $0b, $09, $0a, $08, $03, $01, $02, $00

            ; LOW nibble (3..0)
tx_low
            .byte   $f0, $b0, $e0, $a0, $70, $30, $60, $20
            .byte   $d0, $90, $c0, $80, $50, $10, $40, $00

send        .proc
            ; A = byte
            ; Assumes we are in the sending state:
            ; the host is asserting CLOCK and the device is asserting DATA.

            ; prepare the bits to be sent so we can push them to IEC output
            ; efficiently during the transfer--which is timing critical
            phx
            pha
            lsr     a
            lsr     a
            lsr     a
            lsr     a
            tax
            lda     tx_high,x
            sta     self.temp
            pla
            and     #$0f
            tax
            lda     tx_low,x
            ora     self.temp

            ; Jiffy: wait for device to release DATA, allow interrupts while waiting
            cli
_wait
            jsr     platform.iec.port.test_DATA
            bcs     _ready

            jsr     sleep_20us
            bra     _wait

_ready
            sei
            ldx     #4
            ; Release CLOCK for 11-13 usecs to indicate start of transfer.
            jsr     platform.iec.port.release_CLOCK

            ; Timing now is critical, bit timings in usec after CLOCK release:
            ; (10, 20, 31, 41) send
            jsr     sleep_5us
_loop
            pha
            and     #$03
            ora     #(port.IEC_SREQ_o | port.IEC_ATN_o)
            sta     port.IEC_OUTPUT_PORT
            jsr     sleep_10us

            pla
            lsr     a
            lsr     a
            dex
            bne     _loop

            bit     platform.iec.self.eoi_pending
            bpl     _no_eoi
_eoi
            jsr     platform.iec.port.release_CLOCK ; signal EOI
_no_eoi
            jsr     platform.iec.port.release_DATA
            ; TODO: verify timing
            jsr     sleep_10us

            jsr     platform.iec.port.read_DATA
            bcc     _ack
            DBG_CALL     debug_error
            bra     _end
_ack
            DBG_CALL     debug_ACK
_end
            jsr     platform.iec.port.assert_CLOCK  ; back to idle state asserting CLOCK
            jsr     sleep_20us
            plx
            rts
            .endproc

receive     .proc
            ; (17, 30, 41, 54) receive

            ; Assume not EOI until proved otherwise
            stz     self.rx_eoi

            ; Wait for the sender to have a byte
            stz     self.temp
            phx
            ldx     #4

            ;cli
            sei
_wait1      jsr     platform.iec.port.read_CLOCK
            bcc     _wait1

            jsr     sleep_20us  ; give the drive some time to catch up
            jsr     sleep_20us  ; give the drive some time to catch up
            ;sei

            ; Signal we are ready to receive
            jsr     platform.iec.port.release_DATA

            jsr     sleep_4us
            ; Clock in the bits, 2 at a time, keep the result in temp
_jiffy_read
            jsr     sleep_4us
            lda     port.IEC_INPUT_PORT
            and     #$03
            asl     self.temp
            asl     self.temp
            ora     self.temp
            sta     self.temp
            dex
            bne     _jiffy_read

            ; All bits transferred, now check data signal (EOI indication)
            jsr     sleep_10us

            jsr     platform.iec.port.assert_DATA
            jsr     platform.iec.port.read_CLOCK
            bcc     _no_eoi
            ; Set the EOI flag.
            dec     self.rx_eoi
            DBG_CALL debug_last
_no_eoi
            cli

            ; reshuffle bits to in the correct order
            lda     self.temp
            ldx     #8
            stz     self.temp
_rev_loop
            lsr     a
            rol     self.temp
            dex
            bne     _rev_loop
            lda     self.temp

            plx

            ;DBG_CALL debug_ACK
            DBG_CALL debug_write

            ; Return EOI in NV
            clc
            bit     self.rx_eoi
            ora     #0
            rts
            .endproc

detect      .proc
            ; just return if not running on an X2 core as the timings will be off
            bit     $d6a7
            bmi     _detect
            rts

_detect
            jsr     platform.iec.port.assert_CLOCK
            ; TODO: measure with non jiffy drive to see if this matches 400us at 12MHz
            ldy     #61
_loop
            jsr     platform.iec.port.read_DATA
            bcc     _detected
            dey
            bne     _loop
            rts
_detected
            ldy     #20
_wait_loop
            jsr     platform.iec.port.read_DATA
            bcs     _out
            dey
            bne     _wait_loop
_out
            dec     self.jiffy ; 0 -> ff
            rts
            .endproc


            ; NB: the timing values need not to be taken literally;
            ;     they have been manually adjusted to match Jiffy timings
sleep_4us   .proc
            phx
            ldx     #4
_loop       dex
            bne     _loop
            plx
            rts
            .endproc

sleep_5us   .proc
            phx
            ldx     #6
_loop       dex
            bne     _loop
            plx
            rts
            .endproc

sleep_10us  .proc
            phx
            ldx     #7
_loop       dex
            bne     _loop
            plx
            rts
            .endproc


            .endwith ; platform.iec
            .send ; kernel2
            .endn ; jiffy
            .endn ; platform

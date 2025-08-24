; Jiffy implementation Copyright 2025 Matthias Brukner <mbrukner@gmail.com>
; SPDX-License-Identifier: GPL-3.0-only

            .cpu        "w65c02"


            .namespace  platform
jiffy       .namespace
            .section    kernel2

            .with platform.iec

            ; Screen buffer output debugging
JIFFY_DEBUG = IEC_DEBUG

            ; To debug RX/TX timings you can enable SREQ toggling
            ; on bit timings
TX_DEBUG    = false
RX_DEBUG    = false

MACHINE_ID  = $d6a7
TIMEOUT     = 255

DBG_CALL    .macro routine
            .if JIFFY_DEBUG
            jsr \routine
            .endif
            .endm

delay_y     .macro  x1_delay, x2_delay
            ldy     #\x1_delay
            bit     MACHINE_ID
            bpl     _delay_sel
            ldy     #\x2_delay
_delay_sel
            nop
            nop
_delay      dey
            bne     _delay
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

            ; ------------------------------------------- Jiffy send --------
send        .proc
            ; A = byte
            ; Assumes we are in the sending state:
            ; the host is asserting CLOCK and the device is asserting DATA.

            ; prepare the bits to be sent so we can push them to IEC output
            ; efficiently during the transfer--which is timing critical
            phx
            phy

            .if JIFFY_DEBUG
            pha
            lda     #$0e ; blue
            jsr     debug_set_color
            pla
            jsr     debug_write
            .endif

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

            ; Wait for device to release DATA, allow interrupts while waiting
            cli
            ldx     #TIMEOUT
_wait
            ; Is this enough waiting, are there slower drives? This may be a
            ; situation where having this interrupt driven might be good to
            ; guarantee correct timings, aligned to the drives internal clock
            jsr     platform.iec.port.read_DATA
            bcs     _ready
            dex
            bne     _wait

            ; error -- data not being asserted by device
            ; TODO: follow up on error handling
            ; Clock still being asserted
            ply
            plx
            sec
            rts

_ready
            sei
            ; Release CLOCK for 11-13 usecs to indicate start of transfer.

            ;delay_y 1,6
            ;jsr     platform.iec.port.release_CLOCK
            .port.release IEC_CLK_o

            ; Timing now is critical, bit timings in usec after CLOCK release:
            ; (10, 20, 31, 41) send
            delay_y 9,23
_loop
            pha
            and     #$03
            .if TX_DEBUG
            ora     #(port.IEC_ATN_o)
            .else
            ora     #(port.IEC_SREQ_o | port.IEC_ATN_o)
            .endif
            sta     port.IEC_OUTPUT_PORT
            delay_y 10,26
            pla
            lsr     a
            lsr     a

            pha
            and     #$03
            ora     #(port.IEC_SREQ_o | port.IEC_ATN_o)
            sta     port.IEC_OUTPUT_PORT
            delay_y 8,23
            pla
            lsr     a
            lsr     a

            pha
            and     #$03
            .if TX_DEBUG
            ora     #(port.IEC_ATN_o)
            .else
            ora     #(port.IEC_SREQ_o | port.IEC_ATN_o)
            .endif
            sta     port.IEC_OUTPUT_PORT
            delay_y 8,23
            pla
            lsr     a
            lsr     a

            pha
            and     #$03
            ora     #(port.IEC_SREQ_o | port.IEC_ATN_o)
            sta     port.IEC_OUTPUT_PORT
            delay_y 10,26
            pla
            lsr     a
            lsr     a

            bit     platform.iec.self.eoi_pending
            bpl     _no_eoi
_eoi
            ; staus: EOI
            .if TX_DEBUG
            lda     #(port.IEC_ATN_o | port.IEC_DATA_o | port.IEC_CLK_o)
            .else
            lda     #(port.IEC_ATN_o | port.IEC_SREQ_o | port.IEC_DATA_o | port.IEC_CLK_o)
            .endif
            bra     _send_status
_no_eoi
            ; status: OK
            .if TX_DEBUG
            lda     #(port.IEC_ATN_o | port.IEC_DATA_o)
            .else
            lda     #(port.IEC_ATN_o | port.IEC_SREQ_o | port.IEC_DATA_o)
            .endif
_send_status
            sta     port.IEC_OUTPUT_PORT
            delay_y 11,28

            ; assert clock (in case it wasn't already), also release debug signal
            ;lda     #(port.IEC_ATN_o | port.IEC_SREQ_o | port.IEC_DATA_o | port.IEC_CLK_o)
            lda     #(port.IEC_ATN_o | port.IEC_SREQ_o | port.IEC_DATA_o)
            sta     port.IEC_OUTPUT_PORT

            delay_y 5,14
            jsr     platform.iec.port.read_DATA
            bcc     _ack
            ;DBG_CALL     debug_error
            bra     _end
_ack
            ;DBG_CALL     debug_ACK
_end
            jsr     platform.iec.port.assert_CLOCK  ; back to idle state asserting CLOCK
            jsr     sleep_20us

            ply
            plx
            ;lda     #$f1
            ;DBG_CALL debug_set_color
            rts
            .endproc

            ; ------------------------------------------- Jiffy receive -----
receive     .proc
            ; (17, 30, 41, 54) receive

            ; Assume not EOI until proved otherwise
            stz     self.rx_eoi
            lda     #$0d ; green
            DBG_CALL debug_set_color

            ; Wait for the sender to have a byte
            stz     self.temp
            phx
            phy
            ldx     #4

            ;cli
            sei
_wait1      jsr     platform.iec.port.read_CLOCK
            bcc     _wait1

            delay_y 37,80

            ;sei

            ; Signal we are ready to receive
            jsr     platform.iec.port.release_DATA

            delay_y 4,16
            nop
            nop
            ;nop
            nop
            ; Clock in the bits, 2 at a time, keep the result in temp
_jiffy_read
            delay_y 4,14
            nop
            nop
            nop
            nop
            .if RX_DEBUG
            .port.toggle IEC_SREQ_o
            .endif
            lda     port.IEC_INPUT_PORT
            and     #$03
            asl     self.temp
            asl     self.temp
            ora     self.temp
            sta     self.temp
            dex
            bne     _jiffy_read

            ; All bits transferred, now check data signal (EOI indication)
            delay_y 9,23

            jsr     platform.iec.port.assert_DATA
            jsr     platform.iec.port.read_CLOCK
            .if RX_DEBUG
            .port.toggle IEC_SREQ_o
            .endif
            cli
            bcc     _no_eoi
            ; Set the EOI flag.
            dec     self.rx_eoi
            DBG_CALL debug_last
            ldy     #67
            sty     $D6A8
            stz     $D6A9
            bra     _shuffle_bits
_no_eoi
            sta     $D6A9
            lsr     a
            lsr     a
            sta     $D6A8

_shuffle_bits
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

            ;DBG_CALL debug_ACK
            DBG_CALL debug_write

            ; Return EOI in NV
            clc
            bit     self.rx_eoi
            ora     #0

            ply
            plx

            pha
            lda     #$f1
            ;DBG_CALL debug_set_color
            pla
            rts
            .endproc

            ; ------------------------------------------- Jiffy detection ---
detect      .proc
            phy
            jsr     platform.iec.port.assert_CLOCK
            ldy     #50
            bit     MACHINE_ID
            bpl     _loop
            ldy     #120
_loop
            jsr     platform.iec.port.read_DATA
            bcc     _detected
            dey
            bne     _loop
            ply
            rts
_detected
            ldy     #20
            bit     MACHINE_ID
            bpl     _wait_loop
            ldy     #44
_wait_loop
            jsr     platform.iec.port.read_DATA
            bcs     _out
            dey
            bne     _wait_loop
_out
            sec
            ror     self.jiffy ; 0 -> 80
            ;dec     self.jiffy
            ply
            rts
            .endproc

            .endwith ; platform.iec
            .send ; kernel2
            .endn ; jiffy
            .endn ; platform

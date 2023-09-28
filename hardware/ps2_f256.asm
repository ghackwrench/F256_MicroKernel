; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu        "w65c02"
            .namespace  hardware
            
            .mkstr      ps2_f256_dev,   "f256  "
            .mkstr      ps2_f256_init,  "Foenix PS2 keyboard driver"
            .mkstr      ps2_f256_open,  "Foenix PS2 keyboard opened"

            .namespace  ps2

f256        .macro      BASE=$D640, PORT=0, IRQ=irq.ps2_0, STR=hardware.purple_str

                    .virtual    \BASE
KBD_MSE_CTRL_REG    .byte   ?   ; D640
KBD_MS_WR_DATA_REG  .byte   ?   ; D641
READ_SCAN_REG
KBD_RD_SCAN_REG     .byte   ?   ; D642
MS_RD_SCAN_REG      .byte   ?   ; D643
KBD_MS_RD_STATUS    .byte   ?   ; D644
KBD_MSE_NOT_USED    .byte   ?   ; D645
FIFO_BYTE_COUNT
KBD_FIFO_BYTE_CNT   .byte   ?   ; D646
MSE_FIFO_BYTE_CNT   .byte   ?   ; D647


                    .endv            

vectors     .kernel.device.mkdev    dev

init
        ; Just install our vectors.
    
            jsr     kernel.device.alloc
            bcs     _out

            txa
            jsr     hardware.ps2.auto.init
            
            inc     kernel.thread.lock
            lda     #<vectors
            sta     kernel.src+0
            lda     #>vectors
            sta     kernel.src+1
            jsr     kernel.device.install
            dec     kernel.thread.lock

          ; Associate ourselves with the interrupt
            txa
            ldy     #\IRQ
            jsr     irq.install

            ;lda     #\IRQ
    	    ;jsr     irq.enable
    	    
          ; Log (TODO: event)
            phy
            txa
            tay
            lda     #hardware.ps2_f256_init_str
            jsr     kernel.log.dev_message
            ply

            clc
_out        rts


dev_open    
            jsr     hardware.ps2.auto.open

            lda     #\IRQ
    	    jsr     irq.enable

          ; Flush the port
            php
            sei
            lda     #$10<<\PORT
            sta     KBD_MSE_CTRL_REG
            stz     KBD_MSE_CTRL_REG
            plp

          ; Log (TODO: event)
            phy
            txa
            tay
            lda     #hardware.ps2_f256_open_str
            ;jsr     kernel.log.dev_message
            ply
        
    	    clc
    	    rts
dev_close
            lda     #\IRQ
     	    jmp     irq.disable
dev_data
.if false
            lda #2
            sta io_ctrl
            lda $c000+\PORT
            inc a
            sta $c000+\PORT
            stz io_ctrl
.endif            

_loop
.if false
            lda     FIFO_BYTE_COUNT+\PORT
            beq     _done
.else
            lda     KBD_MS_RD_STATUS
            bit     #1<<\PORT
            bne     _done
.endif
            lda     READ_SCAN_REG+\PORT
            phx
            jsr     hardware.ps2.auto.dev_data
            plx
            bra     _loop
            
_done
            rts
dev_status
            jmp     hardware.ps2.auto.dev_status
dev_fetch
          ; May be called any time; protect registers
            php
            sei
            sta     KBD_MS_WR_DATA_REG
            lda     #2+6*\PORT
            sta     KBD_MSE_CTRL_REG
            stz     KBD_MSE_CTRL_REG
            plp
            rts
dev_set
dev_send
            sec
            rts
dev_get
            phy

            ldy     #hardware.hid_str
            cmp     #kernel.device.get.CLASS
            beq     _found
        
            ldy     #hardware.ps2_f256_dev_str
            cmp     #kernel.device.get.DEVICE
            beq     _found
        
            ldy     #\STR
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

            .endm

            .endn
            .endn


; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu        "w65c02"

            .namespace  hardware

            .mkstr      rtc_init,   "Real-Time Clock"
            .mkstr      bq4802,     "bq4802"

rtc_bq4802  .macro  BASE=$D690, IRQ=irq.rtc

self        .namespace
            .virtual    DevState
this        .byte   ?   ; Copy of the device address
flags       .byte   ?   ; Copy of the original rtc flag bits.
            .endv
            .endn
            
rtc         .namespace
            .virtual    \BASE
SECONDS     .byte   ?
SECONDS_AL  .byte   ?
MINUTES     .byte   ?
MINUTES_AL  .byte   ?
HOURS       .byte   ?
HOURS_AL    .byte   ?
DAY         .byte   ?
DAY_AL      .byte   ?
DAY_OF_WEEK .byte   ?
MONTH       .byte   ?
YEAR        .byte   ?
RATES       .byte   ?
ENABLES     .byte   ?
FLAGS       .byte   ?
CONTROL     .byte   ?
CENTURY     .byte   ?
            .endv
            .endn

vectors     .kernel.device.mkdev    dev

init

        stz     io_ctrl

      ; Verify that we have a valid IRQ id.
        lda     #\IRQ
        jsr     irq.disable
        bcs     _out

      ; Allocate the device table entry.
        jsr     kernel.device.alloc
        bcs     _out
        txa
        sta     self.this,x
        
      ; Install our vectors.
        lda     #<vectors
        sta     kernel.src
        lda     #>vectors
        sta     kernel.src+1
        jsr     kernel.device.install

      ; Associate ourselves with the RTC interrupt
        txa
        ldy     #\IRQ
        jsr     irq.install

        stz     io_ctrl
        lda     #%0000_0111 ; !UTI, !STOP, 24, DST
        sta     rtc.CONTROL
        
      ; Update the kernel's time.
        jsr     report

      ; Configure and enable the IRQ source.
        stz     io_ctrl
        lda     #%0000_1010 ; IRQ every 1/64th of a second.
        sta     rtc.RATES
        lda     #$c0        ; Alarm mask (all $c0 -> every second)
        sta     rtc.SECONDS_AL
        sta     rtc.MINUTES_AL
        sta     rtc.HOURS_AL
        sta     rtc.DAY_AL
        lda     #4          ; PIE (interval alarm)
        ora     #8          ; AEI (time alarm)
        sta     rtc.ENABLES

      ; Enable the hardware interrupt.
        lda     #\IRQ
    	jsr     irq.enable
    	
      ; Clear pending interrupts and force an update.
        jsr     dev_data
        
      ; Log (TODO: event)
        phy
        txa
        tay
        lda     #hardware.rtc_init_str
        jsr     kernel.log.dev_message
        ply

_out    rts       

dev_open
dev_close
dev_set
dev_send
dev_fetch
dev_status
    clc
    rts

dev_data
.if false
  lda #2
  sta io_ctrl
  inc $c001
  stz io_ctrl
.endif

        lda     rtc.FLAGS       ; Clear the IRQ
        sta     self.flags,x
        bit     #8
        bne     report
        bit     #4
        bne     _tick
        
      ; Just a forced reset
        rts

_tick
      ; Add 1 (even) or 2 (odd) to the milliseconds
      ; This will achieve a total of 96 millis/second.
      ; The seconds alarm will perform the reset.
      ; Note: millis are in BCD to match the other values.
        sed
        lda     kernel.time.centis
        lsr     a
        lda     #1
        adc     kernel.time.centis
        sta     kernel.time.centis
        cld

        rts
        
report
      ; Update the kernel's clock
      ; Could lock, but we shouldn't need to.
        stz     kernel.time.centis
        lda     rtc.SECONDS
        sta     kernel.time.seconds
        lda     rtc.MINUTES
        sta     kernel.time.minutes
        lda     rtc.HOURS
        sta     kernel.time.hours
        lda     rtc.MONTH
        sta     kernel.time.month
        lda     rtc.DAY
        sta     kernel.time.day
        lda     rtc.YEAR
        sta     kernel.time.year
        lda     rtc.CENTURY
        lda     #$20    ; I think Paul's just not setting
        sta     kernel.time.century
        
        jsr     kernel.clock.dispatch

.if false
        jsr     kernel.event.alloc
        bcs     _out

        lda     #kernel.event.clock.TICK
        sta     kernel.event.entry.type,y
        jmp     kernel.event.enque
.endif
_out
        rts

dev_get
        phy

        ldy     #hardware.rtc_str
        cmp     #kernel.device.get.CLASS
        beq     _found
        
        ldy     #hardware.bq4802_str
        cmp     #kernel.device.get.DEVICE
        beq     _found
        
        ldy     #hardware.none_str
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
        

; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu    "w65c02"

irq         .namespace

        ; Interrupt Sources
            .virtual    0
frame       .byte       ?
line        .byte       ?
ps2_0       .byte       ?
ps2_1       .byte       ?
timer0      .byte       ?
timer1      .byte       ?
dma         .byte       ?
            .byte       ?
serial      .byte       ?
col0        .byte       ?
col1        .byte       ?
col2        .byte       ?
rtc         .byte       ?
via         .byte       ?
iec         .byte       ?
sdc         .byte       ?
max         .endv
            
        ; Dispatch table
            .section kmem
irqs
irq0        .fill   8
irq1        .fill   8
            .send

        ; Interrupt priotity table
            ;.section    tables
            .section kernel
            .align 256
first_bit:      .byte   0, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0
                .byte   4, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0
                .byte   5, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0
                .byte   4, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0
                .byte   6, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0
                .byte   4, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0
                .byte   5, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0
                .byte   4, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0
                .byte   7, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0
                .byte   4, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0
                .byte   5, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0
                .byte   4, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0
                .byte   6, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0
                .byte   4, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0
                .byte   5, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0
                .byte   4, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0
            .send

            .section    kernel

init:
            pha
            phx
            ldx     $1
            stz     $1

          ; Begin with all interrupts masked.
          ; Begin with all interrupts on the falling edge.
            lda     #$ff
            sta     INT_MASK_REG0
            sta     INT_MASK_REG1
            sta     INT_EDGE_REG0
            sta     INT_EDGE_REG1

          ; Reset any pending flags.
            lda     INT_PENDING_REG0
            sta     INT_PENDING_REG0
            lda     INT_PENDING_REG1
            sta     INT_PENDING_REG1

            ; Polarities aren't presently initialized in the
            ; official Foenix kernel; leaving them uninitialized
            ; here.
            ; lda   #0
            ; sta   INT_POL_REG0
            ; sta   INT_POL_REG2


          ; Install the dummy handler in the reserved device slot.
            lda     #<_dummy
            sta     Devices+0
            lda     #>_dummy
            sta     Devices+1

          ; Register the dummy handler with every interrupt source.
            phx
            ldx     #max-1
_loop       stz     irqs,x
            dex
            bpl     _loop
            plx

          ; Enable IRQs
            cli

            stx     $1
            plx
            pla
            clc
            rts

_dummy
    ; Queue an event for the interrupt or mask the interrupt.
    ; Does NOT attempt to retry if the queue is full.
    ; The kernel will clear the pending flag either way.
    ; Unfortunately, there's no clean way to recover from this type
    ; of failure ... users will just need to set a watchdog timer.

            tax     ; x = bit value
            tya     ; a = group

          ; Allocate an event or bail.
            jsr     kernel.event.alloc
            bcs +

          ; Set group and index.
            sta     kernel.event.entry.irq.group,y
            txa
            sta     kernel.event.entry.irq.bitval,y

          ; Set event type.
            lda     #kernel.event.irq.IRQ
            sta     kernel.event.entry.type,y

          ; Queue.
            jmp     kernel.event.enque

          ; Kernel is out of events; mask the interrupt.
          + tay     ; y = group
            txa     ; a = bit value
            ora     INT_MASK_REG0,y
            sta     INT_MASK_REG0,y
            rts

dispatch:
            
_reg0       
            stz     $1
            lda     INT_MASK_REG0
            eor     #$ff
            and     INT_PENDING_REG0
            beq     _reg1
            tax
            ldy     first_bit,x     ; 0..7
            lda     bit,y           ; 1, 2, 4, ...
            sta     INT_PENDING_REG0
            ldx     irq0,y
            ldy     #0      ; group for userland handlers.
            jsr     kernel.device.dev.data
            bra     _reg0

_reg1       
            stz     $1
            lda     INT_MASK_REG1
            eor     #$ff
            and     INT_PENDING_REG1
            beq     _reg2
            tax
            ldy     first_bit,b,x
            lda     bit,b,y
            sta     INT_PENDING_REG1 ; try moving after
            ldx     irq1,y
            ldy     #1      ; group for userland handlers.
            jsr     kernel.device.dev.data
            bra     _reg1

_reg2 
    ; Ideally, we'd atomically check both PENDING registers
    ; and loop if any show a new interrupt.  This can't be
    ; done on a 6502, but I've tested it on an 816, and it
    ; makes no difference.  Further, I haven't experienced
    ; an interrupt lockup just returning here, so we'll
    ; consider this good for now. 
            rts

bit:        .byte   1,2,4,8,16,32,64,128

install:
    ; IN:   A -> lsb of a vector in Devices
    ;       Y -> requested IRQ ID
            
            cpy     #max
            bcs     _out
    
            sta     irqs,y
_out        rts            


enable:
    ; IN:   A -> requested IRQ ID to enable.
            
            cmp     #max
            bcs     _out

            phx
            phy
            ldy     io_ctrl
            stz     io_ctrl

            jsr     map
            eor     #255    ; clear bit to enable source.
            and     INT_MASK_REG0,x
            sta     INT_MASK_REG0,x

            sty     io_ctrl
            ply
            plx

_out        rts

map:
    ; A = IRQ #
    ; X <- IRQth byte
    ; A <- IRQth bit set
    
          ; Offset X to the IRQth byte.
            ldx     #0
            bit     #8
            beq     _bit
            inx

_bit        and      #7
            phy
            tay
            lda     bit,y
            ply
            rts

disable:
    ; IN:   A -> requested IRQ ID to diable.
            
            cmp     #max
            bcs     _out

            phx
            phy
            ldy     io_ctrl
            stz     io_ctrl
            
            jsr     map
            ora     INT_MASK_REG0,x
            sta     INT_MASK_REG0,x

            sty     io_ctrl
            ply
            plx          
        
_out        rts


        .send
        .endn

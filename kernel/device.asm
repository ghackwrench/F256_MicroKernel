; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu        "w65c02"
            
            .section    pages
Devices     .fill       512
DevState    .fill       512
            .send          

            .namespace  kernel
device      .namespace

iface       .struct
          ; External functions
data        .word   ?       ; Data ready
status      .word   ?       ; Status change
fetch       .word   ?       ; Device requests data to send

          ; Internal functions
open        .word   ?       ; Call to open device
size        .fill   248     ; Continue in the next page

get         .word   ?       ; Call to get device data
set         .word   ?       ; Call to set device data
send        .word   ?       ; Call to send data
close       .word   ?       ; Call to close device
            .ends

mkdev       .macro  PREFIX
            .word   \1_data
            .word   \1_status
            .word   \1_fetch
            .word   \1_open
            .word   \1_get
            .word   \1_set
            .word   \1_send
            .word   \1_close
            .endm

            .virtual    Devices
devices     .dstruct    iface
            .endv

            .section    kernel
            
dev         .namespace
data        jmp     (devices.data,x)
status      jmp     (devices.status,x)
fetch       jmp     (devices.fetch,x)
open        jmp     (devices.open,x)
get         jmp     (devices.get,x)
set         jmp     (devices.set,x)
send        jmp     (devices.send,x)
close       jmp     (devices.close,x)
            .endn

install
    ; IN: kernel.src points to the function table.
            pha
            phy

            phx
            ldy     #0
_loop1      lda     (src),y
            sta     Devices,x
            inx
            iny
            cpy     #8
            bne     _loop1
            plx

            phx
_loop2      lda     (src),y
            sta     Devices+256,x
            inx
            iny
            cpy     #16
            bne     _loop2
            plx

            ply
            pla
            clc
            rts            

            .send

status      .namespace
            .virtual    0
WAKE        .word   ?
LINK_UP     .word   ?
LINK_DOWN   .word   ?
DATA_UP     .word   ?
DATA_DOWN   .word   ?
DATA_ERROR  .word   ?
INTERRUPT   .word   ?
            .endv
            .endn

get         .namespace            
            .virtual    0
CLASS       .byte   ?   ; Return the device class str.
DEVICE      .byte   ?   ; Return the device str.
PORT        .byte   ?   ; Return the port str.
READY       .byte   ?   ; Return non-zero if the device is ready.
            .endv
            .endn

set         .namespace            
            .virtual    0
RX_PAUSE    .word   ?
RX_RESUME   .word   ?
TX_RESUME   .word   ?
CH_ENABLE   .word   ?
CH_DISABLE  .word   ?
REGISTER    .word   ?
VOLUME      .word   ?
            .endv
            .endn


            .section    kmem
entries     .byte       ?       ; List of free device entries
            .send
            
            .section    kernel
init
            stz     entries
            lda     #0
            bra     _next   ; Reserve the first one.
_loop       tax
            jsr     free
_next       clc
            adc     #iface.size
            bne     _loop
            
            clc
            rts

alloc
            sec
            ldx     entries
            beq     _out
            pha 
            lda     Devices,x
            sta     entries
            pla
            clc
_out        rts


free
            pha
            lda     entries
            sta     Devices,x
            stx     entries
            pla
            clc
            rts

queue       .namespace
            .virtual    DevState
head        .byte       ?
tail        .byte       ?
            .endv

init
            stz     head,x
            stz     tail,x
            rts

enque
    ; X = queue, Y = token

            pha

            php
            sei
            lda     tail,x
            sta     kernel.token.entry.next,y
            tya
            sta     tail,x
            plp

            pla
            clc
            rts                        

deque
    ; OUT:  Y = dequed token; carry set on empty

            pha    

            ldy     head,x
            bne     _found

            sec
            ldy     tail,x
            beq     _out
            
          ; Safely take the tail (into y)
            php
            sei
            ldy     tail,x
            stz     tail,x
            plp

          ; Reverse into head
_loop       lda     kernel.token.entry.next,y   ; next in A
            pha                                 ; next on stack
            lda     head,x
            sta     kernel.token.entry.next,y
            tya
            sta     head,x
            ply                                 ; next in Y
            bne     _loop

          ; "Find" the head (just where we left it)
            ldy      head,x

_found      
            lda     kernel.token.entry.next,y
            sta     head,x
            clc
            
_out        pla
            rts
            
            .endn
            .send
            .endn
            .endn


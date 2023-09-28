; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu        "w65c02"
            
            .namespace  kernel
clock       .namespace

            .section    dp
seconds     .byte       ?
waiting     .byte       ?
            .send            

            .virtual    Tokens
time        .byte       ?
device      .byte       ?  
cookie      .byte       ?     
next        .byte       ?
            .endv

            .section    kernel

; TODO: basically identical to delay.asm; replace w/ ADT.

init
            stz     seconds
            stz     waiting
            rts



request
    ; A = abs time.
    
            clc
            bit     user.timer.units
            bmi     done

            lda     user.timer.absolute
            ldx     #0
            bra     queue

insert
    ; X = device, A = time

            sec     ; At least 1            
            adc     seconds
            bra     queue

queue

          ; May be called from userland or kernel space
            phy
            jsr     kernel.token.alloc
            bcs     _out
            
          ; Populate the head
            sta     time,y
            txa
            sta     device,y
            lda     user.timer.cookie
            sta     cookie,y
            
          ; Add to list
            php
            sei
            lda     waiting
            sta     next,y
            sty     waiting
            plp
            
            clc
_out
            ply
done
            lda     seconds
            rts
	
dispatch
          ; We keep our own seconds counter for native byte wrapping.
            inc     seconds

          ; Take the list; we're already in an IRQ handler.
            lda     waiting
            stz     waiting
            
_loop
            tay
            beq     _done
            
            lda     seconds
            cmp     time,y
            bpl     _call
       
          ; Add back to the list.
_retry      ldx     next,y
            lda     waiting
            sta     next,y
            sty     waiting
            txa
            bra     _loop

_call
            ldx     device,y
            beq     _event

            phy
            jsr     kernel.device.dev.status
            ply

_free
            lda     next,y
            jsr     kernel.token.free
            bra     _loop

_event
            tya
            jsr     kernel.event.alloc
            bcc     _send
            tay
            bra     _retry
_send       
            tax
            lda     time,x
            sta     kernel.event.entry.timer.value,y
            lda     cookie,x
            sta     kernel.event.entry.timer.cookie,y
            lda     #kernel.event.timer.EXPIRED
            sta     kernel.event.entry.type,y            
            jsr     kernel.event.enque

            txa
            tay
            bra     _free
                        
_done
            rts


            .send
            .endn
            .endn

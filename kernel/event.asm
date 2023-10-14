; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu        "w65c02"
            
            .namespace  kernel

            .section    pages
Events      .fill       256     ; Events (with "next" pointer")
            .send          

            .namespace  event

kevent_t    .struct
next        .byte   ?
            .dstruct    event_t
            .ends

            .virtual    Events
entry       .dstruct    kevent_t
            .endv

            .virtual    Events+$c000
alias       .dstruct    kevent_t
            .endv

            .section    kmem
entries     .byte       ?       ; free list
in          .byte       ?       ; Incoming events
out         .byte       ?       ; Outgoing events
            .send
            

            .section    kernel

init
          ; Zero the exported counter
            stz     user.events.pending

          ; Initialize the queue
            stz     in
            stz     out

          ; Initialize the free-entry pool
            stz     entries
            ldy     #0
_loop       jsr     zero
            jsr     free
            tya
            clc
            adc     #8
            tay
            bne     _loop
            
            clc
            rts

zero
            lda     #0
            sta     entry+0,y
            sta     entry+1,y
            sta     entry+2,y
            sta     entry+3,y
            sta     entry+4,y
            sta     entry+5,y
            sta     entry+6,y
            sta     entry+7,y
            rts

free
    ; Y = event to free
    ; Thread safe
            pha

_buf
          ; If no page in buf, check ext, else free.
            lda     entry.buf,y
            beq     _ext
            jsr     kernel.page.free
_ext            
          ; If no page in ext, zero the event.
            lda     entry.ext,y
            beq     _zero

          ; If ext==buf, we're done, zero the event.
            cmp     entry.buf
            beq     _zero

          ; Ext contained a different page; free it.
            jsr     kernel.page.free

_zero       
          ; Zero out the event.
            jsr     zero

          ; Free the event.
            php
            sei
            lda     entries
            sta     entry.next,y
            sty     entries
            plp

            pla
            clc
            rts
            
alloc
    ; Y <- next token, or carry set.
    ; Thread safe.
            pha
            php
            sei
            ldy     entries
            beq     _empty
            lda     entry.next,y
            sta     entries
            plp
            pla
            clc
            rts
_empty      plp
            pla
            sec
            rts

enque
    ; Event offset in Y; always succeeds.
            php
            sei
            pha
            lda     in
            sta     entry.next,y
            sty     in
            pla
            plp
            dec     user.events.pending  ; Backwards for BIT.
            clc
            rts
            
deque
    ; OUT:  Y = dequed token; carry set on empty
    ; Only called by the user-thread.

            pha    

            ldy     out
            bne     _found

            sec
            ldy     in
            beq     _out
            
          ; Safely take the whole "in" list.
            php
            sei
            ldy     in
            stz     in
            plp

          ; Reverse the stack in Y into "out"
_loop       lda     entry.next,y
            pha                     ; next on stack
            lda     out
            sta     entry.next,y
            sty     out
            ply                     ; next in Y
            bne     _loop

          ; "Find" the head just where we left it :).
            ldy      out

_found      
            lda     entry.next,y
            sta     out

            inc     user.events.pending ; Backwards for BIT.
            clc
            
_out        pla
            rts
            
            .send
            .endn
            .endn


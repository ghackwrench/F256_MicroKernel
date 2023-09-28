; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

        .namespace  kernel
net     .namespace

        
packet  .namespace
        .virtual    Tokens
dev     .byte       ?   ; Device that received the packet
buf     .byte       ?   ; page containing the packet data
len     .byte       ?   ; length of the data
        .endv
        .endn

        .section    dp
pkt     .byte       ?
buf     .word       ?
len     .byte       ?
alt     .word       ?
        .send        


        .section    kernel

init
        ldx     #4  ; TODO: is this even still valid!?!?!
        jsr     kernel.device.queue.init
        jsr     ip_addr_init
        lda     #0
        sta     kernel.net.ipv4.count
        sta     kernel.net.ipv4.good
        rts
        
ip_addr_init
        phy
        ldy     #0
_loop   lda     _ip,y
        sta     kernel.net.ipv4.ip_addr,y
        iny
        cpy     #4
        bne     _loop
        ply
        clc
        rts
_ip     .byte   192,168,1,17               


accept
    ; A = packet

        sta     kernel.thread.start ; schedule processing.
    
        phy
        tay
        ldx     #4  ; "lower"
        jsr     kernel.device.queue.enque
        ply
        clc
        rts

process
        ldx     #4
        jsr     kernel.device.queue.deque
        bcc     _process
        rts

_process
        sty     pkt

        lda     packet.buf,y
        sta     buf+1
        sta     alt+1
        stz     buf
        stz     alt
        
        lda     packet.len,y
        sta     len
        
        jsr     ipv4.ip_accept
        bcs     free
        
        rts
        
free
        ldy     pkt
pkt_free        
        lda     packet.buf,y
        beq     _out
        jsr     kernel.page.free
_out    jmp     kernel.token.free


        
        .send
        .endn
        .endn
        

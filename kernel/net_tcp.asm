; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

        .cpu        "6502"

        .namespace  kernel
        .namespace  net
        .namespace  ipv4
        
tcp     .struct
ip      .dstruct  kernel.net.ipv4.ip
sport   .fill   2       ; source port (big endian)
dport   .fill   2       ; dest port (big endian)
seq     .fill   4       ; sequence number
ack     .fill   4       ; ack number
offset  .byte   ?       ; Data offset, reserved, 
flags   .byte   ?       ; x,x,urg,ack,psh,rst,syn,fin
window  .fill   2       ; 
check   .fill   2       ; checksum (big endian)
urgent  .fill   2       ; offset to urgent data (not used)
data    .ends        

        .section    kmem
length  .word       ?
        .send        

        .section    kernel

tcp_accept        

      ; Verify the checksum.
        jsr     tcp_checksum
        jsr     check_sum
        bcs     _drop
        
      ; Queue and event.
        jsr     kernel.event.alloc
        bcs     _drop    ; TODO: beep or something
            
        lda     #kernel.event.net.TCP
        sta     kernel.event.entry.type,y
        lda     buf+1
        sta     kernel.event.entry.buf,y
        lda     len
        sta     kernel.event.entry.tcp.len,y
        
      ; TODO: record low bits of src_ip, src_port, and dest_port

        jsr     kernel.event.enque 

      ; Free the token
        ldy     pkt
        jmp     kernel.token.free   
               
_drop
        sec
        rts

tcp_send

    ; y->packet token
        lda     #0
        sta     kernel.net.packet.dev,y
        jmp     kernel.net.accept

tcp_send_buf

    ; 'buf' points to a populated IP+TCP packet with
    ; an uncomputed checksum.  Updates the UDP checksum,
    ; then forwards to ip_send, which updates the IP
    ; checksum and forwards to the interface driver.

      ; Ensure that odd-length packets
      ; are zero padded to an even length

        lda     #0
        ldy     len
        sta     (buf),y

      ; Zero the existing checksum.
        lda     #0
        ldy     #tcp.check
        sta     (buf),y
        iny
        sta     (buf),y

      ; Compute the checksum over the packet data.
        jsr     tcp_checksum

        ;lda     #7
        ;jsr     print_sum

      ; Store the one's complement as the new checksum.
        ldy     #tcp.check
        lda     check_h
        eor     #$ff
        sta     (buf),y
        iny
        lda     check_l
        eor     #$ff
        sta     (buf),y

      ; Forward to IP.
        jmp     ip_route

tcp_checksum

      ; Initialize the sum with the proto and length.
      ; The proto is from the pseudo-header and doesn't 
      ; otherwise appear alone in the packet.  The length 
      ; (in this stack) should be strictly less than 256.

        lda     len
        sec
        sbc     #ip.end
        pha             ; length
        clc
        adc     #6      ; protocol
        sta     check_l
        lda     #0
        sta     check_h

      ; Add the source and dest IP addresses.
        ldy     #ip.src_ip
        lda     #8
        jsr     calc_sum
        
      ; Add in the contents of the TCP section.
        pla                 ; length
        ldy     #ip.end     ; start
        jsr     calc_sum    ; calc sum
        
        rts

        .send
        .endn
        .endn
        .endn

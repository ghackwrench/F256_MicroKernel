; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

        .cpu        "6502"

        .namespace  kernel
        .namespace  net
        .namespace  ipv4
        
udp     .struct
        .fill   ip.end
sport   .fill   2       ; source port (big endian)
dport   .fill   2       ; dest port (big endian)
length  .fill   2       ; length (big endian)
check   .fill   2       ; checksum (big endian)
data    .ends        

        .section    kernel

udp_accept

      ; Make sure the length is <256.
        ldy     #udp.length ; MSB
        lda     (buf),y     
        bne     _drop
        
      ; Verify the checksum.
        jsr     udp_checksum
        jsr     check_sum
        bcs     _drop
        
      ; Handle echo requests directly (good for testing).
        ldy     #udp.dport+0  ; MSB
        lda     (buf),y
        bne     _accept
        ldy     #udp.dport+1  ; LSB
        lda     (buf),y
        cmp     #7
        beq     _echo
        
_accept
        ; Queue and event.
        jsr     kernel.event.alloc
        bcs     _drop    ; TODO: beep or something
            
        ; TODO: fix
        lda     #kernel.event.net.UDP
        sta     kernel.event.entry.type,y
        lda     pkt
        sta     kernel.event.entry.udp.token,y
            
        jmp     kernel.event.enque        
_drop
        sec
        rts

_echo
      ; Swap IPs
        jsr     ip_swap_ip

      ; Swap ports
        lda     #2
        sta     alt+0       ; alt->dest port

        ldy     #udp.sport  ; MSB
        lda     (buf),y
        sta     (alt),y
        lda     #0
        sta     (buf),y     ; $00 of $0007

        iny                 ; LSB
        lda     (buf),y
        sta     (alt),y
        lda     #7
        sta     (buf),y

      ; Send the packet.
        jmp     ip_route
        

udp_send
    ; y->packet token
    ; Should probably queue instead of locking.
        
        lda     #0
        sta     kernel.net.packet.dev,y
        jmp     kernel.net.accept


udp_send_buf

    ; 'buf' points to a populated IP+UDP packet with
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
        ldy     #udp.check
        sta     (buf),y
        iny
        sta     (buf),y

      ; Compute the checksum over the packet data.
        jsr     udp_checksum
        
      ; Store the one's complement as the new checksum.
        ldy     #udp.check
        lda     check_h
        eor     #$ff
        sta     (buf),y
        iny
        lda     check_l
        eor     #$ff
        sta     (buf),y

      ; Forward to IP.
        jmp     ip_route

udp_checksum

      ; Initialize the sum with the proto and length.
      ; The proto is from the pseudo-header and doesn't 
      ; otherwise appear alone in the packet.  The length 
      ; (in this stack) should be strictly less than 256.

        ldy     #ip.proto
        lda     (buf),y

        ldy     #udp.length+1   ; LSB
        clc
        adc     (buf),y

        sta     check_l 
        rol     a
        and     #1
        sta     check_h

      ; Add the source and dest IP addresses.
        ldy     #ip.src_ip
        lda     #8
        jsr     calc_sum
        
      ; Add in the contents of the UDP section.
        ldy     #udp.length+1   ; LSB
        lda     (buf),y
        ldy     #ip.end
        jsr     calc_sum
        
        rts

        .send
        .endn
        .endn
        .endn


; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

        .cpu        "6502"

        .namespace  kernel
        .namespace  net
        .namespace  ipv4
        
icmp    .struct
        .fill   ip.end
type    .byte   ?
code    .byte   ?
check_h .byte   ?
check_l .byte   ?
data    .ends        

        
        .section    kernel

icmp_accept

        lda     #0
        sta     check_l
        sta     check_h
        ldy     #ip.end
        lda     len
        sec
        sbc     #ip.end
        jsr     calc_sum
        jsr     check_sum
        bcs     _out

        ldy     #icmp.type
        lda     (buf),y
        eor     #8  ; ECHO
        beq     echo

        sec
_out    rts

echo
      ; Reply
        ldy     #icmp.type
        lda     #0
        sta     (buf),y
        
      ; Swap the IP addresses
        jsr     ip_swap_ip

      ; Recompute the checksums

      ; Zero the checksums
        lda     #0
        sta     check_l
        sta     check_h
        ldy     #icmp.check_h
        sta     (buf),y
        ldy     #icmp.check_l
        sta     (buf),y

      ; Compute the new checksum
        ldy     #ip.end
        lda     len
        sec
        sbc     #ip.end
        jsr     calc_sum

      ; Inject the new sum
        ldy     #icmp.check_h
        lda     check_h
        eor     #$ff
        sta     (buf),y
        ldy     #icmp.check_l
        lda     check_l
        eor     #$ff
        sta     (buf),y
         
      ; Send via ip_send
        jmp     ip_send     ; TODO: ip_route 


        .send
        .endn
        .endn
        .endn


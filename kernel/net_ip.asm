; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

        .cpu        "6502"

        .namespace  kernel
        .namespace  net
ipv4    .namespace        
        

ip      .struct
verlen  .byte   ?
tos     .byte   ?
len     .word   ?
id      .word   ?
flags   .word   ?
ttl     .byte   ?
proto   .byte   ?
check_h .byte   ?
check_l .byte   ?
src_ip  .fill   4
dest_ip .fill   4
end     .ends

        .section    dp
router  .byte   ?
check_h .byte   ?
check_l .byte   ?
check_x .byte   ?
count   .byte   ?
good    .byte   ?
        .send        

        .section    kmem
ip_addr .fill       4
        .send

        .section    kernel
        
ip_accept

        inc     count
        ldy     count
        lda     #0
        jsr     dprint

      ; Verify the header
        jsr     ip_check
        bcs     _out

      ; Ensure that odd-length packets
      ; are zero padded to an even length

        lda     #0
        ldy     len
        sta     (buf),y

        jmp     ip_dispatch

_out    rts

        
ip_dispatch
        ldy     #ip.proto
        lda     (buf),y
        
        cmp     #1  ; ICMP
        beq     _icmp

        cmp     #6  ; TCP
        beq     _tcp

        cmp     #17 ; UDP
        beq     _udp
        
        sec
_out    rts

_tcp    jmp     tcp_accept
_udp    jmp     udp_accept
_icmp   jmp     icmp_accept

ip_check

      ; Check minimal length
        lda     len
        cmp     #20
        bcc     _drop

      ; Check version
        ldy     #ip.verlen
        lda     #$45
        eor     (buf),y
        bne     _drop
        
      ; Check length
        ldy     #ip.len
        lda     (buf),y
        bne     _drop
        iny
        lda     len     ; physical size
        cmp     (buf),y ; reported size
        bcc     _chk    ; smaller is an error
        ;eor     len
        ;bne     _chk
        
      ; Check flags
        ldy     #ip.flags
        lda     #$3f
        and     (buf),y
        iny
        ora     (buf),y
        bne     _drop

      ; Verify the checksum
        ldy     #0
        sty     check_l
        sty     check_h
        lda     #ip.end
        jsr     calc_sum

        ;jmp     check_sum
        jsr     check_sum
        bcs _drop

        inc     good
        ldy     good
        lda     #3
        jsr     dprint
        rts

_chk   
        tay
        lda     #40
        jsr     dprint
        ldy     #ip.len+1
        lda     (buf),y
        tay
        lda     #44
        jsr     dprint


.if false
        ldy     io_ctrl
        lda     #2
        sta     io_ctrl
        inc     $c000+80*2+9
        sty     io_ctrl        
.endif

        sec
        rts
_drop
.if false
        ldy     io_ctrl
        lda     #2
        sta     io_ctrl
        inc     $c000+80*2+11
        sty     io_ctrl  
.endif        
        sec 
        rts        

dprint rts
        stx     check_x
        tax
        lda     #2
        sta     io_ctrl
        tya
        jsr     print_byte
        lda     #0
        sta     io_ctrl
        ldx     check_x
        rts

print_sum  rts
        stx     check_x
        tax
        lda     #2
        sta     io_ctrl
        lda     check_h
        jsr     print_byte
        lda     check_l
        jsr     print_byte
        lda     #0
        sta     io_ctrl
        ldx     check_x
        rts

check_sum
    ; Carry clear if checksum (in check_l/h) is valid.

        lda     check_l
        and     check_h
        eor     #$ff    ; Zero if good
        cmp     #1      ; Carry set if bad
        rts

calc_sum
    ; IN:   Y = start of data, A = count of bytes
    ;       pkt,alt->data, check is pre-initialized

        stx     check_x
        clc
        adc     #1
        lsr     a
        tax
        lda     #1
        sta     alt+0
        clc
_loop   
        lda     check_l
        adc     (alt),y
        sta     check_l
        lda     check_h
        adc     (buf),y
        sta     check_h
        iny
        iny
        dex
        bne     _loop
        bcc     _done
        inc     check_l
        bne     _done
        inc     check_h
        bne     _done
        inc     check_l
_done
        ldx     check_x
        rts

ip_swap_ip
        lda     #4
        sta     alt+0
        ldy     #ip.src_ip
_loop   lda     (buf),y
        pha
        lda     (alt),y
        sta     (buf),y
        pla
        sta     (alt),y
        iny
        cpy     #ip.dest_ip
        bne     _loop
        rts

ip_route jmp ip_send
        ldy     #ip.dest_ip+3
_loop        
        lda     (buf),y
        cmp     ip_addr-ip.dest_ip,y
        bne     ip_send
        dey
        cpy     #ip.dest_ip-1
        bne     _loop

      ; Self-target
      ; Don't bother re-computing the header checksum.
        jmp     ip_dispatch

ip_send

      ; Zero the existing checksum
        lda     #0

        sta     check_l
        sta     check_h

        ldy     #ip.check_l
        sta     (buf),y
        ldy     #ip.check_h
        sta     (buf),y
        
      ; Compute the new checksum
        ldy     #0
        lda     #ip.end
        jsr     calc_sum

      ; Write the inverted sum

        ldy     #ip.check_l
        lda     check_l
        eor     #$ff
        sta     (buf),y

        ldy     #ip.check_h
        lda     check_h
        eor     #$ff
        sta     (buf),y
        
        jsr     pkt_dump

      ; Send the packet
        ldy     pkt
        ldx     packet.dev,y
        tya  
        jsr     kernel.device.dev.send     
        rts
       
        .cpu    "w65c02"
pkt_dump rts
        phx
        phy

        lda     #2
        sta     $1

        ldx     #0
        
.if false
 ldy pkt
 tya
 jsr _print_byte
 lda packet.dev,y
 jsr _print_byte
 lda packet.buf,y
 jsr _print_byte
 lda packet.dev,y
 tay
 lda kernel.device.devices.send+0,y
 jsr _print_byte
 lda kernel.device.devices.send+1,y
 jsr _print_byte
.endif 

        ldy     #0
_loop   lda     (buf),y
        jsr     print_byte
        iny
        cpy     kernel.net.len
        bne     _loop
        
        lda     #32
_clear  sta     $c000,x
        inx
        bne     _clear

        stz     $1

        ply
        plx
        rts 
             
print_byte
        pha
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        jsr     _print_hex
        pla
        and     #$0f
        jsr     _print_hex
        lda     #32
        bra     _print
_print_hex
        cmp     #10
        bcc     _digit
        adc     #'A'-11
        bra     _print
_digit
        ora     #'0'
_print
        sta     $c000,x
        inx
        rts


        .send
        .endn
        .endn
        .endn
        

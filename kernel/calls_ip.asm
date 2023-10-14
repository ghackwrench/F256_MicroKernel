; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu    "r65c02"

            .namespace  kernel
            
            .section    global


udp_init
        jsr     ip_init
              
      ; Init the proto
        ldy     #kernel.net.ipv4.ip.proto
        lda     #17
        sta     (kernel.args.net.socket),y

        rts            

ip_init
    ; Library call
    ; IN: args.ip.

        phx
        phy

      ; verlen
        ldy     #kernel.net.ipv4.ip.verlen
        lda     #$45
        sta     (kernel.args.net.socket),y
        
      ; tos
        lda     #0
        ldy     #kernel.net.ipv4.ip.tos
        sta     (kernel.args.net.socket),y
        
      ; MSB of len
        iny
        sta     (kernel.args.net.socket),y

      ; id and flags
        ldy     #kernel.net.ipv4.ip.id 
        sta     (kernel.args.net.socket),y
        iny
        lda     #%0100_0000  ; Don't fragment
        sta     (kernel.args.net.socket),y
        lda     #0
        iny
        sta     (kernel.args.net.socket),y
        iny
        sta     (kernel.args.net.socket),y
        iny
        sta     (kernel.args.net.socket),y
        
      ; ttl
        ldy     #kernel.net.ipv4.ip.ttl
        lda     #$40
        sta     (kernel.args.net.socket),y
        
      ; src_ip
        lda     io_ctrl
        pha
        lda     #4
        sta     io_ctrl
        ldx     #0  
        ldy     #kernel.net.ipv4.ip.src_ip
_loop   lda     kernel.net.ipv4.ip_addr+$c000,x
        sta     (kernel.args.net.socket),y
        iny
        inx
        cpx     #4
        bne     _loop
        pla
        sta     io_ctrl

      ; dest_ip
        ldx     #0  
        ldy     #kernel.net.ipv4.ip.dest_ip
_loop2  lda     kernel.args.net.dest_ip,x
        sta     (kernel.args.net.socket),y
        iny
        inx
        cpx     #4
        bne     _loop2

      ; ports -- with endian conversion
        lda     kernel.args.net.src_port+1   ; msb
        sta     (kernel.args.net.socket),y
        iny
        lda     kernel.args.net.src_port+0   ; lsb
        sta     (kernel.args.net.socket),y
        iny
        lda     kernel.args.net.dest_port+1   ; msb
        sta     (kernel.args.net.socket),y
        iny
        lda     kernel.args.net.dest_port+0   ; lsb
        sta     (kernel.args.net.socket),y
        
        ply
        plx
        clc
        rts

.if false        
pkt_copy
        ldy     #6                      ; pkt in a network event
        lda     (kernel.args.event),y   ; Not ideal
        tay                             ; pkt in y
.endif        


pkt_free
        lda     mmu_ctrl
        stz     mmu_ctrl
        pha
        jsr     kernel.net.pkt_free
        pla
        sta     mmu_ctrl
        rts

udp_send
   
        phx
        phy

        ldy     io_ctrl
        phy
        ldy     #4
        sty     io_ctrl

        jsr     send_udp_int

        ply
        sty     io_ctrl
        
        ply
        plx
        rts

udp_recv
        phx
        phy

      ; Map the kernel buffers
        ldy     io_ctrl
        phy
        ldy     #4
        sty     io_ctrl
        
        ldy     kernel.cur_event+$c000
        lda     kernel.event.alias.udp.token,y
        tay
        
      ; point kernel.args.src at the source data
        lda     #28                 ; UDP data offset
        sta     kernel.args.ptr+0   ; LSB
        lda     kernel.net.packet.buf+$c000,y
        ora     #$c0                ; Aliased kernel buffer
        sta     kernel.args.ptr+1   ; MSB

      ; X = # of bytes to copy.
        lda     kernel.net.packet.len+$c000,y
        sec
        sbc     #28     ; IP +UDP
        tax             ; # of bytes to copy.
        cpx     kernel.args.net.buflen
        bcc     _copy
        beq     _copy
        ldx     kernel.args.net.buflen
        
_copy
        stx     kernel.args.net.buflen   ; Bytes copied
        txa
        beq     _done

        phy
        ldy     #0
_loop   lda     (kernel.args.ptr),y
        sta     (kernel.args.net.buf),y
        iny
        dex
        bne     _loop
        ply

_done
        jsr     pkt_free    ; TODO: this should be done by next_event

      ; Restore and return
        ply
        sty     io_ctrl  
        
        ply
        plx
        clc
        rts


send_udp_int
        
        jsr     ip_for_args
        bcs     _out

      ; Protocol    ; TODO: move to init
        ldy     #kernel.net.ipv4.ip.proto
        lda     #17
        sta     (kernel.args.ptr),y

      ; length (total)
        ldy     #kernel.net.ipv4.ip.len
        lda     #0
        sta     (kernel.args.ptr),y
        iny     ; LSB
        lda     kernel.args.net.buflen
        clc
        adc     #28  ; IP+UDP header length
        sta     (kernel.args.ptr),y

      ; length (data)
        ldy     #kernel.net.ipv4.udp.length
        lda     #0
        sta     (kernel.args.ptr),y
        iny     ; LSB
        lda     kernel.args.net.buflen
        clc
        adc     #8  ; UDP header length
        sta     (kernel.args.ptr),y
        
      ; Checksum (computed by the stack)
        iny
        iny
        
      ; Data
        iny
        sty     kernel.args.ptr
        ldy     #0
        bra     _next
_loop
        lda     (kernel.args.net.buf),y
        sta     (kernel.args.ptr),y
        iny
_next
        cpy     kernel.args.net.buflen
        bne     _loop
        stz     kernel.args.ptr

    ; At this point, we can switch to the kernel's map
    ; TODO: create a slot1 alias for the args.
        ldy     mmu_ctrl
        stz     mmu_ctrl
        phy
        ldy     io_ctrl
        stz     io_ctrl
        phy

      ; Allocate a token for the packet
        jsr     kernel.token.alloc
        bcs     _back   ; TODO: free page

        lda     kernel.net.ipv4.router
        sta     kernel.net.packet.dev,y

        lda     $2000+kernel.args.ptr+1 ; TODO:  user.args...
        and     #$1f    ; In the kernel's memory.
        sta     kernel.net.packet.buf,y

        lda     $2000+kernel.args.net.buflen  ; TODO:  user.args...
        adc     #28 ; IP+UDP
        sta     kernel.net.packet.len,y

        jsr     kernel.net.ipv4.udp_send

_back
        ply
        sty     io_ctrl
        ply
        sty     mmu_ctrl        
_out
        rts
        


ip_for_args
      ; Allocate the buffer
        ldy     mmu_ctrl
        stz     mmu_ctrl
        phy
        jsr     kernel.page.alloc_a
        ply
        sty     mmu_ctrl
        bcc     _ok
        rts

_ok
      ; Mount it at kernel.args.ptr.
        ora     #$c0    ; Buffers aliased here.
        sta     kernel.args.ptr+1
        stz     kernel.args.ptr
        
      ; Copy the header from user memory.
        ldy     #0
_loop
        lda     (kernel.args.net.socket),y
        sta     (kernel.args.ptr),y
        iny
        cpy     #kernel.net.ipv4.udp.data
        bne     _loop     

        clc
        rts


            .send
            .endn

; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu    "r65c02"

            .namespace  kernel

tcp         .struct
header      .dstruct    kernel.net.ipv4.tcp
tx_queue    .fill   128
tx_pending  .byte   ?

snd_una     .fill   4   ; Oldest unack'd seq number
snd_nxt     .fill   4   ; Next seq number to send
snd_wnd     .byte   ?   ; Capped at 255
snd_wl1     .fill   4
snd_wl2     .fill   4

rcv_wnd     .word   ?

state       .byte   ?
cookie      .byte   ?
end         .ends

TCP_FIN =    1
TCP_SYN =    2
TCP_RST =    4
TCP_PSH =    8
TCP_ACK =   16
TCP_URG =   32
TCP_FLAGS = 63

            .section    global

small_windows_test
    ; Returns !Z (A!=0) if this is a K with DIP6 set.

            ldy     io_ctrl

          ; If DIP6 (CBM keyboard) is off, nothing else to look at.
            jsr     platform.dips.read
            and     #platform.dips.VIAKBD
            beq     _out

          ; If this is a K (no CBM keyboard), return true
          ; (ie, reduce TCP window size).
            lda     $d6a7
            cmp     #$12
            beq     _out    ; This is a K.
            lda     #0
_out        
            sty     io_ctrl
            ora     #0
            clc
            rts

tcp_open
    ; Running mostly in user-space.
    ; kernel.args.net.socket points to the user's socket block.
    ; kernel.args.net.src/dest/ip contain the init values.
    
            pha
            phx
            phy

    ; Initialize a user-owned socket page (passed in kernel.args.net.socket).

          ; TODO: check the buffer length
            lda     kernel.args.buflen
            cmp     #tcp.end + 1
            ;bcs     _out
            nop
            nop

          ; Init the IP segment
            jsr     kernel.ip_init
            ldy     #kernel.net.ipv4.ip.proto
            lda     #6
            sta     (kernel.args.net.socket),y
            
          ; Use smaller windows if K+DIP6.
            jsr     small_windows_test
            beq     _std_win
            ldy     #kernel.net.ipv4.tcp.seq
-           lda     _small-kernel.net.ipv4.tcp.seq,y
            sta     (kernel.args.net.socket),y
            iny
            cpy     #kernel.net.ipv4.tcp.data+4 ; +opt mss
            bne     -
            bra     _init_seq

_std_win
          ; Copy the initial values
            ldy     #kernel.net.ipv4.tcp.seq
-           lda     _init-kernel.net.ipv4.tcp.seq,y
            sta     (kernel.args.net.socket),y
            iny
            cpy     #kernel.net.ipv4.tcp.data+4 ; +opt mss
            bne     -

_init_seq
          ; Init the seq number; we stuff the tick count at the top.
            ldx     io_ctrl
            lda     #4
            sta     io_ctrl
            lda     kernel.ticks+$C000
            stx     io_ctrl
            ldy     #tcp.header.seq+0
            sta     (kernel.args.net.socket),y

.if true
          ; Init the local port; we stuff the tick count at the top.
            ldx     io_ctrl
            lda     #4
            sta     io_ctrl
            lda     kernel.time.seconds+$C000
            stx     io_ctrl
            ldy     #tcp.header.sport+1
            sta     (kernel.args.net.socket),y
.endif            
          ; Consider the MSS option part of the payload.
            lda     #4
            ldy     #tcp.tx_pending
            sta     (kernel.args.net.socket),y

          ; Init snd_wnd to zero+mss (until we receive a window from the server).
            lda     #4
            ldy     #tcp.snd_wnd
            sta     (kernel.args.net.socket),y

          ; Queue the packet
            lda     #TCP_SYN
            jsr     tcp_reply

          ; Remove the MSS option from subsequent writes.
            lda     #$50
            ldy     #kernel.net.ipv4.tcp.offset
            sta     (kernel.args.net.socket),y
            
          ; "ACK" the MSS option (the SYN is 1, so the ack will zero tx_pending).
            lda     #1
            ldy     #tcp.tx_pending
            sta     (kernel.args.net.socket),y

          ; State is SYN_SENT
            lda     #STATE.SYN_SENT
            ldy     #kernel.tcp.state
            sta     (kernel.args.net.socket),y

            clc
_out        
            ply
            plx
            pla
            rts
            
_init       .byte   $00, $00, $00, $00      ; Initial sequence
            .byte   $00, $00, $00, $00      ; Initial ack
            .byte   $60, $02, $00, $d0      ; One option (MSS), SYN, WIN
            .byte   $00, $00, $00, $00      ; Checksum, urgent
            .byte   $02, $04, $00, $d0      ; MSS = 208 $D0

_small      .byte   $00, $00, $00, $00      ; Initial sequence
            .byte   $00, $00, $00, $00      ; Initial ack
            .byte   $60, $02, $00, $70      ; One option (MSS), SYN, WIN ($70)
            .byte   $00, $00, $00, $00      ; Checksum, urgent
            .byte   $02, $04, $00, $70      ; MSS = 208 $70



tcp_send
    ; Copy what data we can into the send queue and send the packet.
    ; IN:   buf/len -> socket, ext/len -> data
    ; OUT:  accepted = # of bytes accepted
    
            phx
            phy

          ; Return a failure if we aren't established.
            ldy     #tcp.state
            lda     (kernel.args.net.socket),y
            cmp     #STATE.ESTABLISHED
            sec
            bne     _out
          
          ; A = # of bytes remaining in the queue
            ldy     #tcp.tx_pending
            lda     #128
            sec
            sbc     (kernel.args.net.socket),y

          ; Accept what we can fit in the queue;
          ; tcp_queue will limit based on the window.
            cmp     kernel.args.net.buflen
            bcc     _count  ; The queue size is smaller, use it.
            lda     kernel.args.net.buflen
_count      sta     kernel.args.net.accepted
            tax     ; X = # of bytes to copy
            beq     _send    ; No room for more; try to send

          ; A = offset of the append point in the socket
            clc
            lda     #tcp.tx_queue   ; Start of data
            ldy     #tcp.tx_pending ; Add offset from existing data
            adc     (kernel.args.net.socket),y

          ; Point kernel.args.ptr at the append point
            adc     kernel.args.net.socket+0
            sta     kernel.args.ptr+0
            lda     kernel.args.net.socket+1
            adc     #0
            sta     kernel.args.ptr+1

          ; Append the data
            ldy     #0
_loop       lda     (kernel.args.net.buf),y
            sta     (kernel.args.ptr),y
            iny
            dex
            bne     _loop

          ; Update the queue length
            tya
            ldy     #tcp.tx_pending
            clc
            adc     (kernel.args.net.socket),y
            sta     (kernel.args.net.socket),y

_send
          ; Don't try to send if the receiver is busy.
            ldy     #tcp.snd_wnd
            lda     (kernel.args.net.socket),y
            beq     _out
            
          ; Send the packet
            lda     #TCP_ACK|TCP_PSH
            jsr     tcp_reply

_out
            ply
            plx
            rts

socket_match
    ; IN:   net.socket->socket, event contains a packet.
    ; OUT:  carry set if socket doesn't match the packet.

            phx
            phy

          ; Mount the packet in the event at args.ptr
            ldy     #kernel.event.event_t.buf
            lda     (kernel.args.events.dest),y
            ora     #$c0
            sta     kernel.args.ptr+1
            stz     kernel.args.ptr+0

          ; Expose the kernel data
            lda     io_ctrl
            pha
            lda     #4
            sta     io_ctrl

          ; Stash the cookie in the packet's TTL
          ; tcp_recv can use this to verify the association.
          ; TODO: try to move back to the bottom.  Weird failure.
            ldy     #tcp.cookie
            lda     (kernel.args.net.socket),y
            ldy     #tcp.header.ip.ttl
            sta     (kernel.args.ptr),y

          ; Compare our src port to their dest port
            lda     #2  ; Their dest port is +2 our src
            sta     kernel.args.ptr+0
            ldy     #tcp.header.sport
            tax
            jsr     _cmp
            stz     kernel.args.ptr+0
            bcs     _out
          
          ; Compare their dest port to our source port
            ldy     #tcp.header.dport+0
            lda     (kernel.args.ptr),y
            ldy     #tcp.header.sport+0
            eor     (kernel.args.net.socket),y
            cmp     #1
            bcs     _out
            ldy     #tcp.header.dport+1
            lda     (kernel.args.ptr),y
            ldy     #tcp.header.sport+1
            eor     (kernel.args.net.socket),y
            cmp     #1
            bcs     _out
            
          ; Compare our dest IP to their src IP
            lda     #252
            sta     kernel.args.ptr+0
            dec     kernel.args.ptr+1
            ldy     #tcp.header.ip.dest_ip
            ldx     #4
            jsr     _cmp
            stz     kernel.args.ptr+0
            inc     kernel.args.ptr+1
            bcs     _out


_out
            pla
            sta     io_ctrl
            tya
            ply
            plx
            rts 
_cmp
            lda     (kernel.args.net.socket),y
            eor     (kernel.args.ptr),y
            bne     _result
            iny
            dex
            bne     _cmp
_result     cmp     #1      ; Set carry if different
            rts            

tcp_accept
tcp_reject
            sec
            rts

tcp_recv
    ; Copy received data into a user provided buffer (as typical), but
    ; also update the socket state and send an ack.

    ; Current event should contain the packet.
    ; arg should contain:
    ;   - the socket in buf
    ;   - the user buffer in ext/extlen
    ; 
    
            phx
            phy

          ; Try to mount the TCP packet from the current event.
            jsr     packet_mount
           ;ldy     #NotTCP
            bcs     _out

          ; Nothing received until proven otherwise
            stz     kernel.args.net.accepted

          ; Mount the kernel data
            lda     io_ctrl
            pha
            lda     #4
            sta     io_ctrl

          ; Check the socket's cookie against the packet's TTL.
            ldy     #tcp.header.ip.ttl
            lda     (kernel.args.ptr),y
            ldy     #tcp.cookie
            eor     (kernel.args.net.socket),y
            cmp     #1
            bcs     _out
 
          ; Clear the flags (TODO: REMOVE)
            lda     #0
            ldy     #tcp.header.flags
            sta (kernel.args.net.socket),y

          ; Handle the packet based on the state.
            jsr     tcp_dispatch

          ; Return the current socket state.
            ldy     #tcp.state
            lda     (kernel.args.net.socket),y
            tay
            
_out
            pla
            sta     io_ctrl
            tya
            ply
            plx
            rts     
    

tcp_close
            phx
            phy

          ; Send the packet
            lda     #TCP_ACK|TCP_FIN
            jsr     tcp_reply
            clc

            ply
            plx
            rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Packet testing functions

seq_is_valid
  
        ; For now, just verify that it matches our last ack.
        ; Eventually, we should handle packets which straddle
        ; our latest ack.

          ; Quick test packet.seq - socket.ack.
          ; If the numbers match, this packet is acceptable.
            ldy     #tcp.header.seq+3
            lda     (kernel.args.ptr),y
            ldy     #tcp.header.ack+3
            cmp     (kernel.args.net.socket),y
            beq     _ok

          ; Full test packet.seq - socket.ack.
            sec
            ldy     #tcp.header.seq+3
            lda     (kernel.args.ptr),y
            ldy     #tcp.header.ack+3
            sbc     (kernel.args.net.socket),y
            ldy     #tcp.header.seq+2
            lda     (kernel.args.ptr),y
            ldy     #tcp.header.ack+2
            sbc     (kernel.args.net.socket),y
            ldy     #tcp.header.seq+1
            lda     (kernel.args.ptr),y
            ldy     #tcp.header.ack+1
            sbc     (kernel.args.net.socket),y
            ldy     #tcp.header.seq+0
            lda     (kernel.args.ptr),y
            ldy     #tcp.header.ack+0
            sbc     (kernel.args.net.socket),y
            bpl     _drop   ; packet from the future, drop
            bmi     _ack    ; TODO: handle overlap 

          ; If the packet is ahead of us, ack or drop
            bpl     _ack
            
          ; If the packet is behind us, we should check to see
          ; if it none-the-less contains usable data, but for now.
          ; ack or drop.
          
_ack
          ; If the packet contains an RST, drop it.
            ldy     #tcp.header.flags
            lda     (kernel.args.ptr),y
            and     #TCP_RST
            cmp     #1
            bcs     _done
            
          ; Otherwise, ACK the packet and ignore it.
            jsr     gratuitous_ack
            sec
_done
            rts
_ok
            clc
            rts
_drop
            sec
            rts

tcp_data
    ; IN:   kernel.args.ptr -> incoming packet.
    ; OUT:  A = size of TCP payload; Y = start of data.

          ; Get the TCP header size
            ldy     #tcp.header.offset
            lda     (kernel.args.ptr),y
            and     #$f0
            lsr     a
            lsr     a
            
          ; Add the IP header size
            clc     ; SYN bit ... shouldn't be set...
            adc     #kernel.net.ipv4.ip.end
            
          ; Stash the data start
            pha

          ; Negate the total.
            eor     #$ff
            inc     a
            
          ; Add the total packet length
            ldy     #kernel.net.ipv4.ip.len+1   ; LSB
            adc     (kernel.args.ptr),y
            
          ; Pop the data start into Y
            ply
            
            rts
            
sbc_ack
    ; y = compare offset in socket
    ; clear carry to pre-subtract 1 from the result.
    
          ; Push the value of the src long
            lda     (kernel.args.net.socket),y
            pha
            iny
            lda     (kernel.args.net.socket),y
            pha
            iny
            lda     (kernel.args.net.socket),y
            pha
            iny
            lda     (kernel.args.net.socket),y
            pha

          ; Y->ack
            ldy     #tcp.header.ack+3
            
          ; Subtract
            pla
            sbc     (kernel.args.ptr),y
            dey
            pla
            sbc     (kernel.args.ptr),y
            dey
            pla
            sbc     (kernel.args.ptr),y
            dey
            pla
            sbc     (kernel.args.ptr),y

            rts
            
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Packet sending functions

tcp_reply

          ; Set the flags as provided.
            ldy     #tcp.header.flags
            sta     (kernel.args.net.socket),y

          ; Queue the packet
            jmp     tcp_queue

tcp_queue

    ; kernel.args.net.socket contains the packet to send.
    ; We're running in the user map at the time this is called.
 
          ; Alloc a token and a buffer (from the kernel map)
            ldx     mmu_ctrl
            stz     mmu_ctrl
            jsr     kernel.token.alloc      ; Result in Y.
            bcs     _alloc
            jsr     kernel.page.alloc_a     ; Result in A.
            sta     kernel.net.packet.buf,y ; Save it while we have it!
            bcc     _alloc
            jsr     kernel.token.free
            sec
_alloc      stx     mmu_ctrl
            bcs     _out
            
          ; Mount it in our pointer in the user's DP.
            stz     kernel.args.ptr+0
            ora     #$c0
            sta     kernel.args.ptr+1

        ; Copy the data

          ; Save our token pointer.
            phy

          ; Map in the kernel buffers
            ldx     io_ctrl
            lda     #4
            sta     io_ctrl

          ; Compute the copy size
            ldy     #tcp.snd_wnd
            lda     (kernel.args.net.socket),y
            beq     _payload                    ; xfer = window = 0
            ldy     #tcp.tx_pending
            cmp     (kernel.args.net.socket),y
            bcc     _payload                    ; xfer = Window (< tx_pending)
            lda     (kernel.args.net.socket),y  ; xfer = pending (<= window)
_payload    clc
            adc     #tcp.tx_queue               ; Size of the headers

 ; Override the send size
   lda     #tcp.tx_queue    ; size of headers
   ldy     #tcp.tx_pending  ; add queue size
   clc
   adc     (kernel.args.net.socket),y

          ; Store it in the packet length
            ldy     #kernel.net.ipv4.ip.len+1
            sta     (kernel.args.net.socket),y

          ; Copy the data; ends with size still in A.
            pha
            tay
_loop       dey
            lda     (kernel.args.net.socket),y
            sta     (kernel.args.ptr),y
            tya
            bne     _loop
            pla

          ; Restore the user's io_map
            stx     io_ctrl
            
          ; Restore the token pointer
            ply
            
        ; Send the packet
        
          ; Switch to the kernel map for the send
            ldx     mmu_ctrl
            stz     mmu_ctrl

          ; Set the buffer length
            sta     kernel.net.packet.len,y
            
          ; Make the call
            jsr     kernel.net.ipv4.tcp_send

          ; Switch back to the user's map
            stx     mmu_ctrl
            clc
_out        
            rts
                   

gratuitous_ack
    ; This is awkward, but should be infrequent;
    ; an expensive implementation should be okay.

          ; Stash the current ack MSB-to-LSB
            ldy     #tcp.header.ack+0
            ldx     #4
_save       lda     (kernel.args.net.socket),y
            pha       
            iny
            dex
            bne     _save

          ; Replace the current ack with the buffer's end

            jsr     tcp_data
            clc

            ldy     #tcp.header.seq+3
            adc     (kernel.args.ptr),y
            ldy     #tcp.header.ack+3
            sta     (kernel.args.net.socket),y

            ldy     #tcp.header.seq+2
            lda     (kernel.args.ptr),y
            adc     #0
            ldy     #tcp.header.ack+2
            sta     (kernel.args.net.socket),y

            ldy     #tcp.header.seq+1
            lda     (kernel.args.ptr),y
            adc     #0
            ldy     #tcp.header.ack+1
            sta     (kernel.args.net.socket),y

            ldy     #tcp.header.seq+0
            lda     (kernel.args.ptr),y
            adc     #0
            ldy     #tcp.header.ack+0
            sta     (kernel.args.net.socket),y

          ; Send the ack
            lda     #TCP_ACK
            jsr     tcp_reply   ; Okay if we push data...
            
          ; Restore the original ack
            ldy     #tcp.header.ack+3
            ldx     #4
_restore    pla
            sta     (kernel.args.net.socket),y
            dey
            dex
            bne     _restore

            rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Socket adjusting functions

accept_ack

          ; A = expected ack (SEQ + pending)
            clc
            ldy     #tcp.header.seq+3
            lda     (kernel.args.net.socket),y
            ldy     #tcp.tx_pending
            adc     (kernel.args.net.socket),y

          ; Compare it to their ACK.
            ldy     #tcp.header.ack+3
            cmp     (kernel.args.ptr),y

          ; If it isn't a full ACK, ignore it.
            bne     _done

          ; Remove ACK'd bytes from our tx_queue.
          ; TODO: handle incomplete ACKs
            lda     #0
            ldy     #tcp.tx_pending
            sta     (kernel.args.net.socket),y
            
          ; Advance our sequence accordingly

            ldy     #tcp.header.ack+3
            lda     (kernel.args.ptr),y            
            ldy     #tcp.header.seq+3
            sta     (kernel.args.net.socket),y

            ldy     #tcp.header.ack+2
            lda     (kernel.args.ptr),y            
            ldy     #tcp.header.seq+2
            sta     (kernel.args.net.socket),y

            ldy     #tcp.header.ack+1
            lda     (kernel.args.ptr),y            
            ldy     #tcp.header.seq+1
            sta     (kernel.args.net.socket),y

            ldy     #tcp.header.ack+0
            lda     (kernel.args.ptr),y            
            ldy     #tcp.header.seq+0
            sta     (kernel.args.net.socket),y
_done
            rts

accept_seq
            lda     #0
adv_seq            
            pha

          ; Update our copy of the sender's window.
          ; If the window is >255 cap it at 255.
            ldy     #tcp.header.window
            lda     #1
            cmp     (kernel.args.ptr),y
            iny
            lda     (kernel.args.ptr),y
            bcc +
            lda     #255
          + ldy     #tcp.snd_wnd
            sta     (kernel.args.net.socket),y            

          ; Set carry if the header contains a SYN or RST
            ldy     #tcp.header.flags
            lda     (kernel.args.ptr),y
            and     #TCP_SYN | TCP_FIN
            cmp     #1      ; Carry set on SYN

            pla

          ; ack = ptr.seq + flags
          
            ldy     #tcp.header.seq+3
            adc     (kernel.args.ptr),y
            ldy     #tcp.header.ack+3
            sta     (kernel.args.net.socket),y
            
            ldy     #tcp.header.seq+2
            lda     (kernel.args.ptr),y
            adc     #0
            ldy     #tcp.header.ack+2
            sta     (kernel.args.net.socket),y
            
            ldy     #tcp.header.seq+1
            lda     (kernel.args.ptr),y
            adc     #0
            ldy     #tcp.header.ack+1
            sta     (kernel.args.net.socket),y
            
            ldy     #tcp.header.seq+0
            lda     (kernel.args.ptr),y
            adc     #0
            ldy     #tcp.header.ack+0
            sta     (kernel.args.net.socket),y
            
            rts

adv_snd_una

            ldy     #tcp.header.ack+0
            lda     (kernel.args.ptr),y
            ldy     #tcp.snd_una+0
            sta     (kernel.args.net.socket),y
            
            ldy     #tcp.header.ack+1
            lda     (kernel.args.ptr),y
            ldy     #tcp.snd_una+1
            sta     (kernel.args.net.socket),y

            ldy     #tcp.header.ack+2
            lda     (kernel.args.ptr),y
            ldy     #tcp.snd_una+2
            sta     (kernel.args.net.socket),y

            ldy     #tcp.header.ack+3
            lda     (kernel.args.ptr),y
            ldy     #tcp.snd_una+3
            sta     (kernel.args.net.socket),y
            
            rts
            


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Packet processing functions

packet_mount
    ; IN:   current event (must be a TCP packet)
    ; OUT:  args.ptr->packet (under io)

          ; If the current event is not a TCP packet, fail.
            ldy     #kernel.event.event_t.type
            lda     (kernel.args.events.dest),y
            cmp     #kernel.event.net.TCP
            beq     _mount
            sec 
            rts
            
          ; Mount the packet in the event at args.ptr
_mount      ldy     #kernel.event.event_t.buf
            lda     (kernel.args.events.dest),y
            ora     #$c0
            sta     kernel.args.ptr+1
            stz     kernel.args.ptr+0

            clc
            rts


tcp_dispatch   
            ldy     #tcp.state
            lda     (kernel.args.net.socket),y
            tax
            jmp         (_table,x)
_table      .dstruct    STATE            

STATE           .struct
CLOSED          .word   tcp_is_closed
LISTEN          .word   tcp_is_listen
SYN_SENT        .word   tcp_is_syn_sent
SYN_RECEIVED    .word   tcp_is_syn_received
ESTABLISHED     .word   tcp_is_established
FIN_WAIT_1      .word   tcp_is_fin_wait_1
FIN_WAIT_2      .word   tcp_is_fin_wait_2
CLOSE_WAIT      .word   tcp_is_close_wait
CLOSING         .word   tcp_is_closing
LAST_ACK        .word   tcp_is_last_ack
TIME_WAIT       .word   tcp_is_time_wait
                .ends





tcp_is_closed
    ; TODO: make sure kernel.args.net.socket exists
    ; (may need to allocate one)

            ldy     #tcp.header.flags
            lda     (kernel.args.ptr),y
            and     #TCP_ACK
            bne     _ack

          ; SEQ = 0
            lda     #0
            ldy     #tcp.header.seq+0
            sta     (kernel.args.net.socket),y
            iny            
            sta     (kernel.args.net.socket),y
            iny            
            sta     (kernel.args.net.socket),y
            iny            
            sta     (kernel.args.net.socket),y

          ; ACK = ptr.seq+ptr.len
            jsr     tcp_data
            clc
            ldx     #0
            ldy     #tcp.header.seq+3   ; LSB
            adc     (kernel.args.ptr),y
            sta     (kernel.args.net.socket),y
            dey
            txa
            adc     (kernel.args.ptr),y
            sta     (kernel.args.net.socket),y
            dey
            txa
            adc     (kernel.args.ptr),y
            sta     (kernel.args.net.socket),y
            dey
            txa
            adc     (kernel.args.ptr),y
            sta     (kernel.args.net.socket),y
                        
            bra     _rst
_ack
          ; SEQ = ptr.ack
            ldy     #tcp.header.ack
            lda     (kernel.args.ptr),y
            sta     (kernel.args.net.socket),y
            iny
            lda     (kernel.args.ptr),y
            sta     (kernel.args.net.socket),y
            iny
            lda     (kernel.args.ptr),y
            sta     (kernel.args.net.socket),y
            iny
            lda     (kernel.args.ptr),y
            sta     (kernel.args.net.socket),y
_rst        
            ldy     #tcp.header.flags
            lda     (kernel.args.ptr),y
            and     #TCP_ACK
            ora     #TCP_RST
            sta     (kernel.args.net.socket),y
            jmp     tcp_reply

tcp_is_listen
            sec
            rts

tcp_is_syn_sent

            ldy     #tcp.header.flags
            lda     (kernel.args.ptr),y

_1_ack
          ; ACK set?
            ldy     #tcp.header.flags
            lda     (kernel.args.ptr),y
            bit     #TCP_ACK
            beq     _2_rst
            
          ; ACK is set, check ranges.

          ; drop if ACK <= ISS/UNA
            ldy     #tcp.header.seq
            sec
            jsr     sbc_ack
            bpl     _reset

.if false ; later
          ; drop if ACK > snd_next (seq+window)
            ldy     #tcp.snd_next
            sec
            jsr     sbc_ack
            bmi     _reset
.endif
          ; Reload the flags
            ldy     #tcp.header.flags
            lda     (kernel.args.ptr),y            

_2_rst
            bit     #TCP_RST
            beq     _3_sec
            bit     #TCP_ACK
            beq     _drop
_close
            lda     #STATE.CLOSED
            ldy     #tcp.state
            sta     (kernel.args.net.socket),y
           ;ldy     #REJECTED
_drop       
            sec
            rts

_3_sec  ; Not used
_3_prec ; Not used

_4_syn
            bit     #TCP_SYN
            beq     _5
            
            bit     #TCP_ACK
            beq     _estab

          ; Remote has ack'd; advance snd_una
          ; TODO: ACK anything in the TX queue (TTCP)
            jsr     adv_snd_una

_estab
          ; Advance rcv_nxt (next seq we expect to rcv)
            jsr     accept_seq

          ; Advance seq (eg set irs; next seq we send)
            jsr     accept_ack

          ; Check for SND.UNA > ISS (our SYN has been ACKed)
            ; okay for now           

            lda     #STATE.ESTABLISHED
            ldy     #tcp.state
            sta     (kernel.args.net.socket),y

          ; Don't bother with URG &c.
            lda     #TCP_ACK
            jmp     tcp_reply

_synrec
          ; ack = recv.nxt
            jsr     accept_seq

          ; SYN+ACK            
            ldy     #tcp.header.flags
            lda     #TCP_SYN | TCP_ACK
            sta     (kernel.args.net.socket),y

            jmp     tcp_queue

_reset
            ldy     #tcp.header.flags
            lda     (kernel.args.ptr),y
            bit     #TCP_RST
            bne     _drop
            ; TODO: send a reset
            
_5
          ; If not RST, drop.
            bit     #TCP_RST
            beq     _drop
            


tcp_is_syn_received

          ; Our data has been ack'd
            jsr     adv_snd_una
            jsr     accept_ack
            
            jsr     accept_seq
            
          ; ACK            
            ldy     #tcp.header.flags
            lda     #TCP_ACK
            sta     (kernel.args.net.socket),y

            ldy     #tcp.state
            lda     #STATE.ESTABLISHED
            sta     (kernel.args.net.socket),y

            jmp     tcp_queue

tcp_is_established

_1_seq
            jsr     seq_is_valid
            bcc     _2_rst
_drop       clc     ; just ignore them.
            rts
            
_2_rst
          ; If we are not reset, continue.
            ldy     #tcp.header.flags
            lda     (kernel.args.ptr),y   
            bit     #TCP_RST
            beq     _3_secprec
            
          ; We are reset; close.
_close      lda     #STATE.CLOSED
            ldy     #tcp.state
            sta     (kernel.args.net.socket),y
            sec
            rts
            
_3_secprec
          ; Not used
          
_4_syn
            bit     #TCP_SYN
            beq     _5_ack
            lda     #TCP_ACK | TCP_RST
            jsr     tcp_reply
            bra     _close

_5_ack
            bit     #TCP_ACK
            beq     _drop

            jsr     accept_ack

_6_urg
_7_data
          ; Check for incoming bytes
            jsr     tcp_data
            ora     #0
            beq     _8_fin            

          ; Copy incoming bytes

            sty     kernel.args.ptr+0   ; ptr->data
            tax
            ldy     #0
_loop       lda     (kernel.args.ptr),y
            sta     (kernel.args.net.buf),y
            iny
            dex
            bne     _loop
            sty     kernel.args.net.accepted          
            stz     kernel.args.ptr+0
            
          ; A = # of bytes to ack
          ; fall through to _8_fin
            tya
            
_8_fin
          ; Advance our ack # (data size in A)
            jsr     adv_seq

            ldy     #tcp.header.flags
            lda     (kernel.args.ptr),y 
            bit     #TCP_FIN
            beq     _done

            ldy     #tcp.state
            lda     #STATE.CLOSE_WAIT
            sta     (kernel.args.net.socket),y

          ; Ideally, the stack would message the caller
          ; that the far end is done, but it's okay for
          ; our side to continue sending.  For now, at
          ; least, we'll also close.

            lda     #STATE.FIN_WAIT_1
        lda     #STATE.CLOSED
            sta     (kernel.args.net.socket),y

          ; ACK and close
            lda     #TCP_ACK | TCP_FIN
            jmp     tcp_reply
            
_done
          ; ACK
            lda     #TCP_ACK
;            jsr     tcp_reply
; rts
          ; ACK
            lda     #TCP_ACK | TCP_PSH
            jmp     tcp_reply
          
          

tcp_is_fin_wait_1
tcp_is_fin_wait_2
tcp_is_close_wait
tcp_is_closing
tcp_is_last_ack
tcp_is_time_wait
            sec
            rts



            .send
            .endn

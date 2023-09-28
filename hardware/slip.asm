; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu    "65c02"

            .namespace  hardware
            .mkstr      slip_init,  "Serial Line Internet Protocol"
            .endn


            .namespace  kernel
            .namespace  net
slip        .namespace

self        .namespace
            .virtual    DevState

queue       .word   ?   ; token queue
this        .byte   ?   ; Index of self in Packet
upper       .byte   ?   ; Upper driver

rx_buf      .byte   ?
rx_len      .byte   ?   ; Number of bytes received
rx_esc      .byte   ?   ; Negative if escaped character received.
rx_over     .byte   ?   ; non-zero if buffer is in overflow.

            .fill   248

tx_buf      .byte   ?   ; Buffer being transmitted
tx_ptr      .byte   ?   ; Next buffer index to transmit
tx_len      .byte   ?   ; Length of buffer being transmitted
tx_esc      .byte   ?   ; Escaped character to transmit

            .endv
            .endn

        .section    kernel
 
vectors     .kernel.device.mkdev    slip
       
init
    ; OUT:  X = SLIP device

          ; Allocate the device table.
            jsr     kernel.device.alloc
            bcs     _out
      
          ; Init
            txa
            sta     self.this,x

          ; Install our vectors.
            lda     #<vectors
            sta     kernel.src
            lda     #>vectors
            sta     kernel.src+1
            jsr     kernel.device.install

        phy
        txa
        tay
        lda     #hardware.slip_init_str
        jsr     kernel.log.dev_message
        ply

_out        
            rts       

slip_open
    ; Y = upper; A = bps

          ; Save the upper driver.
            pha
            tya
            sta     self.upper,x
            pla

          ; Open the upper driver with a=BPS, y=this.
            phx
            ldy     self.this,x
            ldx     self.upper,y
            jsr     kernel.device.dev.open
            plx
            bcs     _out

          ; Init state
            jsr     kernel.device.queue.init          

            stz     self.rx_buf,x
            stz     self.rx_len,x            
            stz     self.rx_esc,x            
            stz     self.rx_over,x

            stz     self.tx_buf,x
            stz     self.tx_esc,x
            stz     self.tx_ptr,x
            stz     self.tx_len,x

.if false
        phy
        ldy     self.upper,x
        lda     #hardware.open_str
        jsr     kernel.log.dev_message
        ply
.endif        

_out        rts
            

SLIP_END     = 192
SLIP_ESC     = 219
SLIP_ESC_END = 220
SLIP_ESC_ESC = 221

slip_data

    ; A=byte, X=SLIP

        phy

_retry  

      ; Handle END byte
        cmp     #SLIP_END          ; An END always means END.
        beq     _end

      ; Handle overrun
        ldy     self.rx_over,x     ; Ignore everything else in overrun.
        bne     _done

      ; Handle ESC byte
        cmp     #SLIP_ESC
        beq     _esc

      ; Handle ESC arg
        ldy     self.rx_esc,x
        bne     _unesc

_append 
        ldy     self.rx_buf,x
        beq     _alloc

_data
        stz     irq_tmp
        sty     irq_tmp+1
        ldy     self.rx_len,x
        sta     (irq_tmp),y
        inc     self.rx_len,x
        beq     _over

_done   
        ply
        clc
        rts

_over   ; TODO: report?
        dec     self.rx_over,x
        stz     self.rx_len,x
        bra     _done

_esc    
        sta     self.rx_esc,x
        bra     _done

_unesc  
        stz     self.rx_esc,x

        cmp     #SLIP_ESC_ESC
        bne     _unend

        lda     #SLIP_ESC
        bra     _append

_unend  
        cmp     #SLIP_ESC_END
        bne     _error

        lda     #SLIP_END
        bra     _append

_alloc
        tay
        jsr     kernel.page.alloc_a
        bcs     _over
        sta     self.rx_buf,x
        stz     self.rx_len,x
        tya
        ldy     self.rx_buf,x
        bra     _data


_error  
        dec     self.rx_over,x
        bra     _retry              ; Might be an END.


_end    
        lda     self.rx_over,x
        bne     _drop

        lda     self.rx_len,x
        beq     _done               ; Karn packet
        
        lda     self.rx_esc,x
        bne     _drop

        jsr     kernel.token.alloc
        bcs     _drop
        
        txa
        sta     kernel.net.packet.dev,y
        lda     self.rx_buf,x
        sta     kernel.net.packet.buf,y
        lda     self.rx_len,x
        sta     kernel.net.packet.len,y

        tya
        ldy     self.this,x
        jsr     kernel.net.accept
        ldx     self.this,y
        stz     self.rx_buf,x
        stz     self.rx_len,x
        bra     _done
        
_drop
        stz     self.rx_len,x
        stz     self.rx_over,x
        stz     self.rx_esc,x
        jmp     _done
        

slip_status:
        cmp     #kernel.device.status.DATA_ERROR
        beq     _over
        sec
        rts
_over   sta     self.rx_over,x
        clc
        rts        

slip_fetch:
    ; Stream is ready for another byte from us
    ; X->this, Y->UART, return next byte in A or set carry (done for now)

        phy
        
      ; Complete any previous escapes.
        lda     self.tx_esc,x
        bne     _unesc
      
      ; Get the buffer
        lda     self.tx_buf,x
        beq     _empty

_retry

      ; Point to the next byte to send.
        lda     self.tx_ptr,x

      ; Are we at the end?
        cmp     self.tx_len,x
        beq     _finish
        
      ; Read the next byte to send.
        sta     irq_tmp+0
        lda     self.tx_buf,x
        sta     irq_tmp+1
        lda     (irq_tmp)
        inc     self.tx_ptr,x

      ; Is it something we need to escape?
        cmp     #SLIP_ESC
        beq     _esc
        cmp     #SLIP_END
        beq     _end

_send   clc

_done   ply  
        rts

_unesc  lda     self.tx_esc,x
        stz     self.tx_esc,x
        bra     _send

_empty
        jsr     kernel.device.queue.deque
        bcs     _done

.if false
        phy
        ldy     io_ctrl
        lda     #2
        sta     io_ctrl
        lda     $c000+2*80+10
        dec a
        and #7
        ora #48
        sta     $c000+2*80+10
        sty     io_ctrl
        ply
.endif        


        lda     kernel.net.packet.buf,y
        sta     self.tx_buf,x
        lda     kernel.net.packet.len,y
        sta     self.tx_len,x
        stz     self.tx_ptr,x
        jsr     kernel.token.free
        bra     _retry

_finish
        lda     self.tx_buf,x
        stz     self.tx_buf,x
        jsr     kernel.page.free

        lda     #SLIP_END
        bra     _send


_esc    lda     #SLIP_ESC_ESC       ; Queue an ESC_ESC
_queue  sta     self.tx_esc,x
        lda     #SLIP_ESC           ; Send an ESC
        bra     _send
_end    lda     #SLIP_ESC_END       ; Queue an ESC_END
        bra     _queue



slip_get
        phy

        ldy     #hardware.net_str
        cmp     #kernel.device.get.CLASS
        beq     _found
        
        ldy     #hardware.slip_str
        cmp     #kernel.device.get.DEVICE
        beq     _found
        
        ldy     #hardware.none_str
        cmp     #kernel.device.get.PORT
        beq     _found
        
        sec
        bra     _out

_found
        tya
        clc        
_out
        ply
        rts


slip_set
        sec
        rts
        
slip_send
        phy

        tay
        jsr     kernel.device.queue.enque

        lda     self.upper,x
        tax
        lda     #kernel.device.set.TX_RESUME
        jsr     kernel.device.dev.set

.if false
        ldy     io_ctrl
        lda     #2
        sta     io_ctrl
        lda     $c000+2*80+10
        inc a
        and #7
        ora #48
        sta     $c000+2*80+10
        sty     io_ctrl
.endif        

        ply
        clc
        rts
        

slip_close
        lda     self.upper,x
        tax
        jmp     kernel.device.dev.close
        

        .send
        .endn
        .endn
        .endn

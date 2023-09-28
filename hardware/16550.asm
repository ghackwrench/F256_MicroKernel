; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu    "w65c02"

            .namespace  hardware
           
            .mkstr  init,   "Init: slot #."
            .mkstr  open,   "Open: #."

            .mkstr  serial, "com   "
            .mkstr  slip,   "slip  "
            .mkstr  uart,   "16550 "
            .mkstr  db9,    "DB9F  "
            .mkstr  none,   "      "
            .mkstr  uart_init,   "Serial port driver"

        
u16550      .macro  BASE=$cdf0, DIVISORS=0, IRQ=irq.serial, LINES=0


self        .namespace
            .virtual    DevState

this        .byte   ?   ; Copy of the device address
lower       .byte   ?   ; Device offset of lower handler
modem       .byte   ?   ; Modem line status bits
lines       .byte   ?   ; ORed in line status bits
fifo        .byte   ?   ; # of remaining tx fifo slots
error       .byte   ?   ; error bits
hold        .byte   ?

            .endv
            .endn
            
            .virtual    \BASE

UART_TRHB   .byte   ?   ; Transmit/Receive Hold Buffer
UART_IER    .byte   ?   ; Interupt Enable Register
UART_FCR    .byte   ?   ; FIFO Control Register
UART_LCR    .byte   ?   ; Line Control Register
UART_MCR    .byte   ?   ; Modem Control REgister
UART_LSR    .byte   ?   ; Line Status Register
UART_MSR    .byte   ?   ; Modem Status Register
UART_SR     .byte   ?   ; Scratch Register

UART_DLL  = UART_TRHB   ; Divisor Latch Low Byte
UART_DLH  = UART_IER    ; Divisor Latch High Byte
UART_IIR  = UART_FCR    ; Interupt Indentification Register

            .endv


vectors     .kernel.device.mkdev    uart

init

      ; Verify that we have a valid IRQ id.
        lda     #\IRQ
        jsr     irq.disable
        bcs     _out

      ; Close the device
        jsr     close

      ; Allocate the device table.
        jsr     kernel.device.alloc
        bcs     _out
        
        txa
        sta     self.this,x
        
      ; Install our vectors.
        lda     #<vectors
        sta     kernel.src
        lda     #>vectors
        sta     kernel.src+1
        jsr     kernel.device.install

      ; TODO: port should adapt for wifi
        phy
        txa
        tay
        lda     #hardware.uart_init_str
        jsr     kernel.log.dev_message
        ply

_out    rts       

close
        lda     #0
        sta     UART_MCR
        sta     UART_IER
        lda     #FCR_FIFO_ENABLE | FCR_CLEAR_RX | FCR_CLEAR_TX | FCR_RX_FIFO_8
        sta     UART_FCR        
        rts


uart_open:
    ; should param lower handler
    ; X->UART, Y->lower, A=BPS [8..15]

      ; Save the provided lower handler
        pha
        tya
        sta     self.lower,x
        pla
        bcs     _out

      ; Try to match the port speed.
        jsr     \DIVISORS
        bcs     _out

      ; Open the divisor latch.
        pha
        lda     #LCR_8N1 | LCR_DLB
        sta     UART_LCR
        pla
 
      ; Set the BPS
        sta     UART_DLH
        tya
        sta     UART_DLL
        
      ; Enable 64-byte fifo
        lda     #32
        sta     UART_FCR

      ; Close the divisor latch; 8N1.
        lda     #LCR_8N1
        sta     UART_LCR
        
      ; Clear any data errors
        lda     UART_LSR
.if false
      ; Grab and forward a modem-status baseline.
        lda     UART_LSR        ; should be clean
        ldy     self.this,x
        jsr     send_status
        ldx     self.this,y
.endif
      ; Initialize the FIFOs.
        lda     #FCR_FIFO_ENABLE | FCR_CLEAR_RX | FCR_CLEAR_TX | FCR_RX_FIFO_8 | 32
        sta     UART_FCR

        ; Configure receive interrupts (and clean up UART state).
        lda     #UINT_DATA_AVAIL | UINT_MODEM_STATUS | UINT_LINE_STATUS
        sta     UART_IER

      ; Install the interrupt handler
        txa
        ldy     #\IRQ
        jsr     irq.install
        
      ; Enable the hardware interrupt.
        lda     #\IRQ
    	jsr     irq.enable
    	
        ; Raise DTR and RTR, enable interrupts from the chip.
        lda     #MCR_DTR | MCR_RTS | MCR_OUT2
        sta     UART_MCR

.if false
        phy
        ldy     self.lower,x
        lda     #hardware.open_str
        jsr     kernel.log.dev_message
        ply
.endif

        jmp     tx_resume
        clc
        
_out    rts

send_status:
    ; Report changes to DSR, RI, CD
    
        lda     self.modem,y
        sta     self.hold,y

        lda     UART_MSR
        ora     self.lines,y
        ora     #\LINES
        sta     self.modem,y

        ldx     self.this,y

; Changes to CTS
        bit     #MSR_DCTS
        beq     _ects
        jsr     dcts
        lda     self.modem,y
_ects

; Changes to DSR
        bit     #MSR_DDSR
        beq     _edsr
        jsr     ddsr
        lda     self.modem,y
_edsr                
    
; Changes to CD    
        bit     #MSR_DCD
        beq     _edcd
        jsr     send_cd
        lda     self.modem,y
_edcd
        
; Ring
        bit     #MSR_TERI
        beq     _eri
        lda     #kernel.device.status.WAKE
        jsr     kernel.device.dev.status
_eri

        rts


ddsr    ; TODO
        clc
        rts

dcts
        bit     #MSR_CTS
        bne     tx_resume

        php
        sei
        lda     UART_IER
        and     #~UINT_THR_EMPTY
        sta     UART_IER
        plp
        cli
        rts        
        

send_cd
        bit     #MSR_CD
        beq     _down
        lda     #kernel.device.status.DATA_UP
        jmp     kernel.device.dev.status
_down   lda     #kernel.device.status.DATA_DOWN
        jmp     kernel.device.dev.status


uart_get
        phy

        ldy     #hardware.serial_str
        cmp     #kernel.device.get.CLASS
        beq     _found
        
        ldy     #hardware.uart_str
        cmp     #kernel.device.get.DEVICE
        beq     _found
        
        ldy     #hardware.db9_str
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

uart_set
        cmp     #kernel.device.set.TX_RESUME
        beq     tx_resume

        cmp     #kernel.device.set.RX_PAUSE
        beq     rx_pause
        
        cmp     #kernel.device.set.RX_RESUME
        beq     rx_resume

        ldx     #kernel.err.REQUEST
        sec
        rts
        
tx_resume
    ; Enable transmit interrupts.
    ; Could pre-load the first byte.

        php
        sei
        ;lda     UART_MSR
        ;ora     self.lines,x
        ;bit     #MSR_CTS
        ;beq     _done       ; DCE is busy.

        lda     UART_IER
        ora     #UINT_THR_EMPTY
        sta     UART_IER

_done   plp
        clc
        rts

rx_pause
      ; Requested sender pause (drop RTR)
        php
        sei
        lda     UART_MCR
        ora     #MCR_RTS
        sta     UART_MCR
        plp
        clc
        rts

rx_resume
      ; Request sender resume (raise RTR)
        php
        sei
        lda     UART_MCR
        ora     #MCR_RTS
        sta     UART_MCR
        plp
        clc
        rts

uart_send
        php
        sei
        tax

        lda     UART_IER
        bit     #UINT_THR_EMPTY
        bne     _busy

        lda     UART_LSR
        bit     LSR_XMIT_EMPTY
        beq     _busy

        txa
        sta     UART_TRHB

        plp
        clc
        rts
_busy
        plp
        txa
        ldx     #kernel.err.BUSY
        sec
        rts


uart_close
      ; Reset the device
        jsr     close
    
      ; Disable the hardware interrupt.
        lda     #\IRQ
    	jmp     irq.disable
    	
uart_fetch
uart_status
        sec
        rts

uart_data

      ; Switch to Y.
        ldy     self.this,x

uart_loop
        lda     UART_IIR
        bit     #1
        bne     _done   ; Spurious interrupt.
        and     #6
        tax
        jmp     (_table,x)
_done   ;lda     UART_LSR    ; May also need to dispatch the LSR itself.
        ;bit     #1
        ;bne     uart_rx
        rts

_table  .word   uart_lines
        .word   uart_tx
        .word   uart_rx
        .word   uart_err


uart_lines
        ;jsr    send_status
        lda     UART_MSR
        bra     uart_loop 

uart_rx
        lda     UART_LSR
        bit     #1
        beq     uart_loop
        lda     UART_TRHB
        ldx     self.lower,y
        jsr     kernel.device.dev.data
        bcc     uart_rx
        bra     uart_loop

.if false
uart_rx2
        lda     UART_TRHB
        ldx     self.lower,y
        jsr     kernel.device.dev.data
        ;bcs     uart_loop ; No flow control on the Jr.
        lda     UART_LSR
        bit     #1
        bne     uart_rx
        bra     uart_loop

      ; abandoned flow control; note, the 16750 can do this in hardware.
        lda     UART_MCR
        and     #+~MCR_RTS
        sta     UART_MCR
        bra     uart_loop
.endif
        
uart_err
        lda     UART_LSR
        
.if false
 lda #2
 sta io_ctrl
 dec $c000+80*2+8
 stz io_ctrl
.endif
        bra     uart_loop        

        sta     UART_SR
        ldx     self.lower,y

      ; Report breaks
        lda     UART_SR
        bit     #LSR_BREAK_INT
        bne     _bdone
        lda     #kernel.device.status.INTERRUPT
        jsr     kernel.device.dev.status
_bdone        
                
      ; Report data errors
        lda     UART_SR
        bit     #LSR_ERR_FRAME | LSR_ERR_PARITY
        bne     _edone
        lda     #kernel.device.status.DATA_ERROR
        jsr     kernel.device.dev.status
_edone        

        bra     uart_loop


uart_tx
        lda     #16             ; FIFO length
        sta     self.fifo,y
_cont   ldx     self.lower,y
        jsr     kernel.device.dev.fetch
        bcs     _tx_off
        sta     UART_TRHB
        ldx     self.this,y
        dec     self.fifo,x
        bne     _cont
        jmp     uart_loop

_tx_off lda     UART_IER
        and     #~UINT_THR_EMPTY
        sta     UART_IER
        jmp     uart_loop



; Interupt Enable Flags
UINT_LOW_POWER = $20        ; Enable Low Power Mode (16750)
UINT_SLEEP_MODE = $10       ; Enable Sleep Mode (16750)
UINT_MODEM_STATUS = $08     ; Enable Modem Status Interrupt
UINT_LINE_STATUS = $04      ; Enable Receiver Line Status Interupt
UINT_THR_EMPTY = $02        ; Enable Transmit Holding Register Empty interrupt
UINT_DATA_AVAIL = $01       ; Enable Recieve Data Available interupt   

; Interrupt Identification Register Codes
IIR_FIFO_ENABLED = $80      ; FIFO is enabled
IIR_FIFO_NONFUNC = $40      ; FIFO is not functioning
IIR_FIFO_64BYTE = $20       ; 64 byte FIFO enabled (16750)
IIR_MODEM_STATUS = $00      ; Modem Status Interrupt
IIR_THR_EMPTY = $02         ; Transmit Holding Register Empty Interrupt
IIR_DATA_AVAIL = $04        ; Data Available Interrupt
IIR_LINE_STATUS = $06       ; Line Status Interrupt
IIR_TIMEOUT = $0C           ; Time-out Interrupt (16550 and later)
IIR_INTERRUPT_PENDING = $01 ; Interrupt Pending Flag

; Line Control Register Codes
LCR_DLB = $80               ; Divisor Latch Access Bit
LCR_SBE = $60               ; Set Break Enable

LCR_PARITY_NONE = $00       ; Parity: None
LCR_PARITY_ODD = $08        ; Parity: Odd
LCR_PARITY_EVEN = $18       ; Parity: Even
LCR_PARITY_MARK = $28       ; Parity: Mark
LCR_PARITY_SPACE = $38      ; Parity: Space

LCR_STOPBIT_1 = $00         ; One Stop Bit
LCR_STOPBIT_2 = $04         ; 1.5 or 2 Stop Bits

LCR_DATABITS_5 = $00        ; Data Bits: 5
LCR_DATABITS_6 = $01        ; Data Bits: 6
LCR_DATABITS_7 = $02        ; Data Bits: 7
LCR_DATABITS_8 = $03        ; Data Bits: 8

LCR_8N1 = LCR_DATABITS_8 | LCR_PARITY_NONE | LCR_STOPBIT_1

LSR_ERR_RECIEVE = $80       ; Error in Received FIFO
LSR_XMIT_DONE = $40         ; All data has been transmitted
LSR_XMIT_EMPTY = $20        ; Empty transmit holding register
LSR_BREAK_INT = $10         ; Break interrupt
LSR_ERR_FRAME = $08         ; Framing error
LSR_ERR_PARITY = $04        ; Parity error
LSR_ERR_OVERRUN = $02       ; Overrun error
LSR_DATA_AVAIL = $01        ; Data is ready in the receive buffer

MCR_DTR =   1
MCR_RTS =   2
MCR_OUT1 =  4
MCR_OUT2 =  8
MCR_TEST = 16

FCR_FIFO_ENABLE = 1
FCR_CLEAR_RX    = 2
FCR_CLEAR_TX    = 4
FCR_RX_FIFO_1   = 0
FCR_RX_FIFO_4   = 64
FCR_RX_FIFO_8   = 128
FCR_RX_FIFO_14  = 192  ; Total is 16, so this is pushing things.

MSR_DCTS    =   1
MSR_DDSR    =   2
MSR_TERI    =   4
MSR_DCD     =   8
MSR_CTS     =  16
MSR_DSR     =  32
MSR_RI      =  64
MSR_CD      = 128

UART_300 = 384              ; Code for 300 bps
UART_1200 = 96              ; Code for 1200 bps
UART_2400 = 48              ; Code for 2400 bps
UART_4800 = 24              ; Code for 4800 bps
UART_9600 = 12              ; Code for 9600 bps
UART_19200 = 6              ; Code for 19200 bps
UART_38400 = 3              ; Code for 28400 bps
UART_57600 = 2              ; Code for 57600 bps
UART_115200 = 1             ; Code for 115200 bps

UART_DCTS   =   1
UART_DDSR   =   2
UART_TERI   =   4
UART_DDCD   =   8
UART_CTS    =  16
UART_DSR    =  32
UART_RI     =  64
UART_DCD    = 128

        .endm
        .endn

; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

; The main kernel code receives its various memory and buffer pools from
; hardware specific startup code like this.
;
; On the Jr, MMU0 is reserved for the micro-kernel.  Doing so
; reduces the IRQ overhead.

; The SDCard's F_SD_WP_i and F_SD_CD_i are located @ $D6A0
; Bit[7] = F_SD_WP_i
; Bit[6] = F_SD_CD_i

            .cpu    "w65c02"

*           = $0000     ; Kernel Direct-Page
mmu_ctrl    .byte       ?
io_ctrl     .byte       ?
reserved    .fill       6
mmu         .fill       8
fat32       .fill       32  ; MMU LUT full-view.
            .dsection   dp
            .cerror * > $00ef, "Out of dp space."

*           = $0100     ; Just beyond the FPGA registers
Stack       .fill       256
            .dsection   pages
            .dsection   kmem    ; ragged
            .align      256
Buffers     .fill       0

            .namespace  kernel
            .virtual    $20f0
user        .dstruct    kernel.args_t
            .endv
            .endn

*           = $4000     ; Kernel tables start here
            .dsection   tables
Strings     .dsection   strings ; aligned
            .align      256
magic2      .byte       <MAGIC
            .dsection   kernel
            .dsection   kernel2
            .cerror * >= $8000, "Out of kernel space."

*           = $8000     ; Fat32 starts here
fat_base
            .dsection   fat32_code
            .cerror * >= $c000, "Out of kernel space."

*           = $e000 ; Kernel code starts here.
            .dsection   startup
            .dsection   global
            .cerror * > $feff, "Out of global space."


*           = $ffe0
            .word   0                   ; ffe0 816 reserved
            .word   0                   ; ffe2 816 reserved
            .word   platform.hw_cop     ; ffe4 816 native COP
            .word   platform.hw_brk     ; ffe6 816 native BRK
            .word   platform.hw_abort   ; ffe8 816 native ABORT
            .word   platform.hw_nmi     ; ffea 816 native NMI
            .word   0                   ; ffec 816 reserved
            .word   platform.hw_int     ; ffee 816 native IRQ

*           = $fff4 ; Hardware vectors.
            .word   platform.hw_cop     ; fff4 COP
wait_upload bra     wait_upload         ; fff6 Not used on 6502
            .word   platform.hw_abort   ; fff8 65816 emulation ABORT
            .word   platform.hw_nmi     ; fffa NMI
            .word   platform.hw_reset   ; fffc RESET
            .word   platform.hw_irq     ; fffe IRQ/BRK

            .section    fat32_code
            .binary     "../fat32.bin"
            .send

platform    .namespace

            .section    dp
irq_io      .byte       ?   ; io_ctrl when an IRQ fires.
irq_mmu     .byte       ?   ; mmu_ctrl when an IRQ fires.
            .send            

            .section    startup     ; The following is ALWAYS at $E000
signature   .null      "KERNEL"
magic       .byte       <MAGIC
paul_date   .null       DATE_STR
            .align      32
            
hw_reset:

        sei

      ; Always switch to the startup code in flash
      ; RAM and ROM should always be identical here.
        lda     #$80
        sta     mmu_ctrl
        lda     #$7f
        sta     mmu+7
        
      ; If DIP1 is off, continue with the flash kernel
        stz     io_ctrl
        lda     $d670   ; Read Jr dip switch register.
        eor     #$ff    ; Values are inverted.
        bit     #1
        beq     _start

      ; Check for a RAM kernel
        ldy     #$0c    ; $01:6000 / $13:6000 -- doesn't cross I/O memory
        sty     mmu+1
        ldx     #0
_loop   lda     $2000,x
        cmp     signature,x
        bne     _start
        inx
        cpx     #6
        bne     _loop
        
      ; Signature found, switch to the RAM kernel at $E000
        sty     mmu+7
        
_start
    ; Below this line, kernels may be different

      ; If this is a 65816, switch pin 3 from an input
      ; (for PHI0-out) to a 1 output (for ABORTB-in).
        .cpu    "65816"
        clc
        xce
        bcc     +
        sec
        xce
        stz     io_ctrl
        lda     #$03
        sta     $d6b0
+      .cpu    "w65c02"        

      ; Allocate physical slot 6 for our ZP; this will
      ; allow us to create a more typical mapping for
      ; process zero.
        lda     #6
        sta     mmu+0
        
      ; Pre-mount the user process's ZP ($00) at $2000.
        stz     mmu+1
        
      ; fat32 BSS is the RAM under $E000
      ;  lda     #7
      ;  sta     mmu+2

      ; 2,3,4,5 are the blocks preceeding the kernel
        lda     mmu+7
        sec
        sbc     #4
        sta     mmu+2
        inc     a
        sta     mmu+3
        inc     a
        sta     mmu+4
        inc     a
        sta     mmu+5

      ; 6 is the kernel's ZP
        lda     mmu+0
        sta     mmu+6

      ; Copy the map to MMU1
        ldx     #0      
_copy   lda     mmu,x           ; Read from MMU0
        ldy     #%10_01_0000    ; edit MMU1
        sty     mmu_ctrl
        sta     mmu,x           ; Store to MMU1
        ldy     #%10_00_0000    ; edit MMU0
        sty     mmu_ctrl
        inx
        cpx     #8
        bne     _copy
        
      ; Change slot 1 in MMU1 to point to FAT32's RAM.
        ldy     #%10_01_0000    ; edit MMU1
        sty     mmu_ctrl
        lda     #7
        sta     mmu+1
        ldy     #%10_00_0000    ; edit MMU1
        sty     mmu_ctrl

      ; Kernel already installed at 7.
      ; Re-lock the MMU
        stz     mmu_ctrl

      ; Zero the stack page for ease of debugging.
        ldx     #0
_zero   stz     Stack,x
        inx
        bne     _zero

      ; Initialize the stack pointer
        ldx     #$ff
        txs        

      ; Initialize the console 
        jsr     console.init    ; Can now trash font in $a000
        jsr     console.welcome
        stz     io_ctrl

      ; Check for mismatched kernel halves
        lda     magic2
        cmp     magic
        bne     upload

      ; Init LCD (if there is one)
        jsr     k2lcd.init      ; Go Init the LCD (if it is a K2 Optical Keyboard)

      ; Init the IRQs and enable
        jsr     irq.init

      ; Export a page pool -- merge with kernel start.
        lda     #>Buffers
        jsr     kernel.page.init

      ; Start the kernel
        jmp     kernel.init

upload
_write      ldy     #0
_loop       lda     _msg,y
            beq     _out
            jsr     puts
            iny
            bra     _loop
_out        bra     _out
_msg        .null   "Upload."  


hardware_init
        jsr     platform.iec.IOINIT
        jsr     clock.init
        jsr     keyboard.init
        jsr     serial.init
        jsr     audio.init
        jsr     hardware.iec.init   ; The kernel driver, NOT the hw.
        jsr     hardware.fat32.init
        rts

nmi:
break:
sys_exit:
        lda     #2
        sta     $1
        lda     $c002
        inc     a
        sta     $c002
        jmp     sys_exit
        
yield
        wai
        rts

hw_nmi: 
        pha
        lda     io_ctrl
        pha
        lda     #2
        sta     io_ctrl
        inc     $c001
        pla
        sta     io_ctrl
        pla
        rti

hw_cop: rti     ; 816 extention; ignore for now.
hw_brk: rti     ; 816 extention; ignore for now.
hw_int: rti     ; 816 IRQ; ignore for now (could save/irq/restore)

hw_abort:
    ; 816 extension.
        rti

hw_irq:  
        pha
        phx
        phy

      ; Save MMU state and switch to the kernel's MMU table.
        lda     mmu_ctrl    ; Get the current mmu state.
        stz     mmu_ctrl    ; Switch to the kernel's mmu table.

hw_swi
        pha

      ; Save the io state.
        lda     io_ctrl
        pha
                
        jsr     irq.dispatch            ; May request kernel services.

      ; Don't start the kernel service if it's already running.
        lda     kernel.thread.running   ; True if kernel service is already running.
        bne     hw_rti

      ; Don't start the kernel service if it hasn't been requested.
        lda     kernel.thread.start     ; True if kernel service is requested.
        beq     hw_rti

      ; Run the kernel service.
        sta     kernel.thread.running   ; Mark the service as running.
        stz     kernel.thread.start     ; Any requests after this point are new.
        cli                             ; Re-enable interrupts.
        jsr     kernel.thread.service   ; Run the service.
        stz     kernel.thread.running   ; Mark the service as no longer running.

hw_rti
        pla
        sta     io_ctrl

        pla
        sta     mmu_ctrl
        
        ply
        plx
        pla
        rti

puts        jmp     platform.console.puts

board       .struct     id, codec
mid         .byte       \id
codec_init  .byte       \codec
size        .ends
            
boards      .dstruct    board, $02,%00000011  ; jr/mmu
_2          .dstruct    board, $12,%00010011  ; k/mmu
_3          .dstruct    board, $22,%00011101  ; jr2/mmu
_4          .dstruct    board, $11,%00011111  ; k2/mmu
boards_end  = * - boards           

get_board
    ; OUT: X -> offset in boards table or carry set on error.
            clc
            ldx     #0
          - lda     boards.mid,x
            eor     $d6a7   ; MID
            and     #$3f
            beq +
            txa
            adc     #board.size
            tax
            cpx     #boards_end
            bne -                     
          + rts


        .send
        .endn


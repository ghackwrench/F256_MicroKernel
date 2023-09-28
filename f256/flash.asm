; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .namespace  kernel
flash       .namespace
            
header      .namespace
            .virtual    $4000
signature   .word       ?
block_count .byte       ?
start_slot  .byte       ?
start_addr  .word       ?
version     .word       ?
kernel      .word       ?
name        .fill       0
            .endv     
            .endn       

            .section    kmem
prompt      .byte       ?
programs    .fill       8
            .send

            .section    global

            
is_rom
    ; IN: X = physical block to test

          ; Enable mmu editing
            lda     #$80
            sta     mmu_ctrl

          ; Stash the slot at $4000 (Fat32 BSS)
            lda     mmu+2
            pha
            
          ; Mount the header block
            stx     mmu+2       ; $4000

          ; Confirm signature
            lda     header.signature+0
            eor     #$f2
            bne     _done
            lda     header.signature+1
            eor     #$56
            bne     _done
_done
          ; Carry set if the signatures didn't match
            cmp     #1

          ; Restore the mount at $4000
            pla
            sta     mmu+2

          ; Disable mmu editing
            stz     mmu_ctrl

          ; Return the result in the carry
            rts    

start_rom
    ; X = ROM to start
    ; NOTE: uses kernel slot 2

          ; Enable mmu editing
            lda     #$80
            sta     mmu_ctrl

          ; Stash the slot at $4000 (Fat32 BSS)
            lda     mmu+2
            pha
            
          ; Mount the header block in our address space
            stx     mmu+2       ; $4000

          ; Y = kernel slot for user_init
            ldy     mmu+7       

          ; Init the user's MMU LUT (RAM+kernel)
          ; IN:  Y = the kernel's kernel slot
          ; OUT: Y = the user's zero slot
            jsr     user_init
            
          ; Mount the user's slot0 in our slot1
            sty     mmu+1   ; Redundant

          ; Install the ROMs in the user's map
            jsr     load_roms

          ; Get the start address in x/y
            ldx     header.start_addr+0
            ldy     header.start_addr+1
            
          ; Restore the RAM under $4000
            lda     #$80
            sta     mmu_ctrl
            pla
            sta     mmu+2

          ; Switch to the user's map
            lda     #%10_11_00_11   ; editing 3, running 3
            sta     mmu_ctrl        ; Now on user's stack.
            stz     io_ctrl

          ; Start the process
            jsr     _start          ; user returns here.
            stz     mmu_ctrl        ; restore the kernel map
            stz     io_ctrl
            jmp     kernel.start_flash

_start
            phy
            phx
            php
            rti

user_init
    ; IN:  Y = block at $E000
    ; OUT: Y = block at $0000
    
         ; Stash the current mmu_ctrl setting
            lda     mmu_ctrl
            pha

         ; Edit mmu3
            lda     #%10_11_0000    ; Edit MMU3
            sta     mmu_ctrl

          ; Slot 7 is the kernel
            sty     mmu+7

          ; Fill slots 0..6 with RAM.
          ; Physical 6 = virtual 6 = kernel RAM.
            ldy     #0
_loop       tya
            sta     mmu,y
            iny
            cpy     #7
            bne     _loop            

          ; Y = user's slot0
            ldy     mmu+0

          ; Restore MMU and return
            pla
            sta     mmu_ctrl            
            clc
            rts

load_roms
    ; x = ROM to load
    ; ROM header mapped at $4000

         ; Stash the current mmu_ctrl setting
            lda     mmu_ctrl
            pha

          ; Edit the user's address space
            lda     #%10_11_0000    ; Edit MMU3
            sta     mmu_ctrl

            txa
            ldx     header.block_count
            ldy     header.start_slot
_loop
          ; Don't install anything after $bfff
            cpy     #6
            bcs     _done

          ; Install the next block
            sta     mmu,y
            inc     a
            iny

            dex
            bne     _loop
_done

          ; Restore original MMU setting
            pla
            sta     mmu_ctrl
            rts


start_by_number
            ldx     kernel.args.run.block_id
            stz     mmu_ctrl
            jmp     start_rom

start_by_name:

          ; Running directly in the user's map
            phx
            phy

          ; Save current mmu settings and enable editing
            lda     mmu_ctrl
            pha
            ora     #$80
            sta     mmu_ctrl

          ; Save current io settings and enable RAM
            lda     io_ctrl
            pha
            lda     #4
            sta     io_ctrl
            
          ; Search for the requested ROM
            jsr     search_expansion
            bcc     _found
            jsr     search_flash
            bcc     _found

          ; Restore the kernel map
            lda     #6
            sta     mmu+6
            
          ; Restore io and mmu
            pla
            sta     io_ctrl
            pla
            sta     mmu_ctrl

          ; Restore x and y and return
            ply
            plx
            rts
            
_found
          ; Switch to the kernel map and chain
            stz     mmu_ctrl
            jmp     start_rom

search_flash
            ldx     #$40
_loop       jsr     is_named_rom
            bcc     _out
            cpx     #$7c
            bcc     _loop
_out        rts

search_expansion
            ldx     #$80
_loop       jsr     is_named_rom
            bcc     _out
            cpx     #$a0
            bcc     _loop
_out        rts

is_named_rom
            stx     mmu+6
            
          ; Test signature
            lda     header.signature+$8000
            eor     #$f2
            bne     _signature
            lda     header.signature+$8001
            eor     #$56
_signature  cmp     #1
            bcc     _name
            inx
            rts                        
            
          ; Test name
_name       ldy     #0
_loop       lda     (kernel.args.buf),y
            cmp     header.name+$8000,y
            bne     _case
            cmp     #0
            beq     _found
_matched    iny
            bra     _loop
_found      clc
            rts
_case
          ; If in alpha range, flip the case and retry.
            cmp     #'A'
            bcc     _nope
            cmp     #'z'+1
            bcs     _nope
            eor     #32
            cmp     header.name+$8000,y
            beq     _matched
_nope
          ; No match, advance to next potential block.
            txa
            clc
            adc     header.block_count+$8000
            tax
            sec
            rts

list_roms
            lda     #'a'
            sta     prompt
            ldx     #$41
 ;ldx     #16
 ;ldx     #32
_loop
          ; Mount the header block in our address space
            lda     #$80
            sta     mmu_ctrl
            stx     mmu+2       ; $4000
            stz     mmu_ctrl

          ; Confirm signature
            lda     header.signature+0
            eor     #$f2
            bne     _done
            lda     header.signature+1
            eor     #$56
            bne     _done

          ; Print the prompt
            lda     prompt
            jsr     platform.console.puts
            lda     #')'
            jsr     platform.console.puts
            lda     #' '
            jsr     platform.console.puts
            
          ; Print the ROM
            jsr     print_rom
            lda     #$0a
            jsr     platform.console.puts

          ; Add it to the list
            lda     prompt
            sec
            sbc     #'a'
            tay
            txa
            sta     programs,y
            
          ; Advance the prompt
            inc     prompt

          ; Advance to next would-be program
            txa
            clc
            adc     header.block_count
            tax
            bra     _loop
            
_done
            rts

print_rom
    ; X = ROM to print

          ; Mount the header block in our address space
            lda     #$80
            sta     mmu_ctrl
            stx     mmu+2       ; $4000
            stz     mmu_ctrl

          ; Print its name
            lda     #<header.name
            sta     src+0
            lda     #>header.name
            sta     src+1
         
            ldy     #0
_loop       lda     (src),y
            beq     _done
            jsr     platform.console.puts
            iny
            bra     _loop
_done       
            rts            
_test       .text   "Is this thing on?",0

_print
            pha
            lsr a
            lsr a
            lsr a
            lsr a
            jsr _hex
            pla
            and #$0f
            jsr _hex
            lda #32
_putch
            sta $c000,x
            inx
            rts
_hex
            phy
            tay
            lda _digit,y
            ply
            bra _putch
_digit      .text   "0123456789abcdef"            
            




            .send
            .endn
            .endn
            
